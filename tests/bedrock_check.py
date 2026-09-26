#!/usr/bin/env python3
"""The upstream Bedrock suites over the native bedrock-converse-stream API.

Upstream mocks the AWS SDK client; here each named case runs
packages/ai/test/bedrock.bend against a loopback server that answers with
real AWS event-stream frames (or an error response), asserts the upstream
expectations, and, for streamed cases, compares the payload onPayload saw,
the onResponse value, every event and the final message with upstream
bedrock-converse-stream.ts driving the real AWS SDK against the same server
(packages/ai/test/bedrock-oracle.ts, Node). Cases that inspect the SDK
client configuration print the configuration the port builds instead.
"""
from upstream_pin import UPSTREAM
import argparse
import base64
import http.server
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import threading
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/ai/test/bedrock.bend"
ORACLE = ROOT / "packages/ai/test/bedrock-oracle.ts"
REGISTERED = ROOT / "packages/coding-agent/test/registered-apis.bend"
AUTH = ROOT / "packages/ai/test/amazon-bedrock-auth.bend"
REQUEST_ID = "req-123"
REDACTED = bytes(range(1, 40))
REDACTED_BASE64 = base64.b64encode(REDACTED).decode()


def header(name, value):
    n, v = name.encode(), value.encode()
    return bytes([len(n)]) + n + bytes([7]) + struct.pack(">H", len(v)) + v


def frame(headers, payload):
    encoded = b"".join(header(k, v) for k, v in headers)
    body = json.dumps(payload).encode()
    total = 12 + len(encoded) + len(body) + 4
    prelude = struct.pack(">II", total, len(encoded))
    prelude += struct.pack(">I", zlib.crc32(prelude))
    message = prelude + encoded + body
    return message + struct.pack(">I", zlib.crc32(message))


def event(kind, payload):
    return frame([(":event-type", kind), (":content-type", "application/json"), (":message-type", "event")], payload)


def exception(kind, payload):
    return frame([(":exception-type", kind), (":content-type", "application/json"), (":message-type", "exception")], payload)


def error_frame(code, message):
    return frame([(":error-code", code), (":error-message", message), (":message-type", "error")], {})


def events(*items):
    return [event(kind, payload) for kind, payload in items]


class Server:
    """Answers every POST with one scripted response."""

    def __init__(self, frames=None, status=200, headers=None, body=None, drop=False):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                outer.requests.append({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(raw) if raw else None})
                if drop:
                    self.close_connection = True
                    return
                data = body.encode() if body is not None else b"".join(frames or [])
                self.send_response(status)
                self.send_header("content-type", "application/json" if status != 200 else "application/vnd.amazon.eventstream")
                self.send_header("x-amzn-requestid", REQUEST_ID)
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}"

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()


BASE_ENV = {k: v for k, v in os.environ.items() if not k.startswith("AWS_") and k not in ("PI_CACHE_RETENTION",)}
KEYS = {"AWS_ACCESS_KEY_ID": "AKIDEXAMPLE", "AWS_SECRET_ACCESS_KEY": "secretexample", "AWS_REGION": "us-west-2", "AWS_BEDROCK_FORCE_HTTP1": "1"}


def parse(output):
    lines = {"event": [], "payload": [], "response": [], "result": [], "config": []}
    for line in output.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in lines:
            lines[kind].append(json.loads(rest))
    return lines


def run(command, spec, env):
    result = subprocess.run([*command, json.dumps(spec)], capture_output=True, text=True, timeout=120, env=env)
    if result.returncode != 0:
        raise AssertionError((command, spec, result.returncode, result.stdout, result.stderr))
    return parse(result.stdout)


def oracle(spec, env):
    result = subprocess.run(["node", str(ORACLE), json.dumps(spec)], capture_output=True, text=True, timeout=120, env=dict(env, PI_MONO=str(UPSTREAM)))
    if result.returncode != 0:
        raise AssertionError(("oracle", spec, result.stdout, result.stderr))
    return parse(result.stdout)


EVENT_KEYS = {
    "start": {"type", "partial"}, "text_start": {"type", "contentIndex", "partial"}, "text_delta": {"type", "contentIndex", "delta", "partial"},
    "text_end": {"type", "contentIndex", "content", "partial"}, "thinking_start": {"type", "contentIndex", "partial"},
    "thinking_delta": {"type", "contentIndex", "delta", "partial"}, "thinking_end": {"type", "contentIndex", "content", "partial"},
    "toolcall_start": {"type", "contentIndex", "partial"}, "toolcall_delta": {"type", "contentIndex", "delta", "partial"},
    "toolcall_end": {"type", "contentIndex", "toolCall", "partial"}, "done": {"type", "reason", "message"}, "error": {"type", "reason", "error"},
}


def normalized(value, typed=False):
    if isinstance(value, dict):
        keys = EVENT_KEYS.get(value.get("type"), value.keys()) if typed else value.keys()
        return {k: ("<time>" if k == "timestamp" else normalized(v)) for k, v in value.items() if k in keys}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    return value


def trace(lines):
    return {
        "payload": lines["payload"],
        "response": [{"status": r["status"], "headers": {k: v for k, v in r["headers"].items() if k not in ("date", "server", "connection", "keep-alive")}} for r in lines["response"]],
        "events": [normalized(e, True) for e in lines["event"]],
        "result": [normalized(r) for r in lines["result"]],
    }


class Case:
    def __init__(self, suite, name, spec, check, server=None, env=None, differential=True, message=True):
        self.suite, self.name, self.spec, self.check = suite, name, spec, check
        self.server, self.env, self.differential, self.message = server, env, differential, message


def hello():
    return {"messages": [{"role": "user", "content": "hello", "timestamp": 1}]}


def message(lines):
    return lines["result"][0]


# --- Case definitions ------------------------------------------------------

CASES = []


def case(*args, **kwargs):
    CASES.append(Case(*args, **kwargs))


def config_case(suite, name, check, spec=None, env=None):
    case(suite, name, dict({"mode": "config", "model": {"catalog": "us.anthropic.claude-opus-4-8"}, "context": hello(), "options": {"cacheRetention": "none"}}, **(spec or {})), check, env=env, differential=False)


def expect(condition, detail=None):
    if not condition:
        raise AssertionError(detail)


# bedrock-credentials.test.ts
AMBIENT = {"AWS_ACCESS_KEY_ID": "AKIAEXAMPLE", "AWS_SECRET_ACCESS_KEY": "secretexample"}
config_case("bedrock-credentials", "prefers explicit and scoped profiles over ambient AWS access keys (explicit)", lambda c, _: expect(c.get("profile") == "explicit-profile" and "credentials" not in c, c), {"options": {"cacheRetention": "none", "profile": "explicit-profile"}}, AMBIENT)
config_case("bedrock-credentials", "prefers explicit and scoped profiles over ambient AWS access keys (scoped)", lambda c, _: expect(c.get("profile") == "scoped-profile" and "credentials" not in c, c), {"options": {"cacheRetention": "none", "env": {"AWS_PROFILE": "scoped-profile"}}}, AMBIENT)
config_case("bedrock-credentials", "uses ambient AWS access keys when no profile is configured", lambda c, _: expect("profile" not in c and c.get("credentials") == {"accessKeyId": "AKIAEXAMPLE", "secretAccessKey": "secretexample"}, c), env=AMBIENT)
config_case("bedrock-credentials", "uses ambient AWS access keys when only an ambient profile is set", lambda c, _: expect(c.get("profile") == "ambient-profile" and c.get("credentials") == {"accessKeyId": "AKIAEXAMPLE", "secretAccessKey": "secretexample"}, c), env=dict(AMBIENT, AWS_PROFILE="ambient-profile"))

# bedrock-endpoint-resolution.test.ts
EU = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
config_case("bedrock-endpoint-resolution", "assigns eu-central-1 runtime URLs to built-in EU inference profiles", lambda c, _: expect(c.get("endpoint") == "https://bedrock-runtime.eu-central-1.amazonaws.com", c), {"model": {"catalog": EU}})
config_case("bedrock-endpoint-resolution", "does not pin standard AWS endpoints when AWS_REGION is configured", lambda c, _: expect(c.get("region") == "us-east-2" and "endpoint" not in c, c), env={"AWS_REGION": "us-east-2"})
config_case("bedrock-endpoint-resolution", "derives region from a built-in EU endpoint when no region or profile is configured", lambda c, _: expect(c.get("endpoint") == "https://bedrock-runtime.eu-central-1.amazonaws.com" and c.get("region") == "eu-central-1", c), {"model": {"catalog": EU}})
config_case("bedrock-endpoint-resolution", "handles missing regions for explicit, scoped, and ambient profiles (explicit)", lambda c, _: expect(c.get("profile") == "bedrock-profile" and c.get("endpoint") == "https://bedrock-runtime.eu-central-1.amazonaws.com" and c.get("region") == "eu-central-1", c), {"model": {"catalog": EU}, "options": {"cacheRetention": "none", "profile": "bedrock-profile"}})
config_case("bedrock-endpoint-resolution", "handles missing regions for explicit, scoped, and ambient profiles (scoped)", lambda c, _: expect(c.get("profile") == "scoped-bedrock-profile" and c.get("endpoint") == "https://bedrock-runtime.eu-central-1.amazonaws.com" and c.get("region") == "eu-central-1", c), {"model": {"catalog": EU}, "options": {"cacheRetention": "none", "env": {"AWS_PROFILE": "scoped-bedrock-profile"}}})
config_case("bedrock-endpoint-resolution", "handles missing regions for explicit, scoped, and ambient profiles (ambient)", lambda c, _: expect(c.get("profile") == "ambient-bedrock-profile" and "endpoint" not in c and "region" not in c, c), {"model": {"catalog": EU}}, {"AWS_PROFILE": "ambient-bedrock-profile"})
config_case("bedrock-endpoint-resolution", "still passes custom Bedrock endpoints through to the SDK client", lambda c, _: expect(c.get("endpoint") == "https://bedrock-vpc.example.com" and c.get("region") == "us-west-2", c), {"model": {"catalog": "us.anthropic.claude-opus-4-8", "baseUrl": "https://bedrock-vpc.example.com"}}, {"AWS_REGION": "us-west-2"})
config_case("bedrock-endpoint-resolution", "extracts region from inference profile ARN regardless of AWS_REGION", lambda c, _: expect(c.get("region") == "us-west-2", c), {"model": {"catalog": "us.anthropic.claude-opus-4-8", "id": "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/abc123"}}, {"AWS_REGION": "us-east-1"})
config_case("bedrock-endpoint-resolution", "extracts region from GovCloud inference profile ARN", lambda c, _: expect(c.get("region") == "us-gov-west-1", c), {"model": {"catalog": "us.anthropic.claude-opus-4-8", "id": "arn:aws-us-gov:bedrock:us-gov-west-1:123456789012:application-inference-profile/abc123"}}, {"AWS_REGION": "us-east-1"})
config_case("bedrock-endpoint-resolution", "preserves ambient AWS auth for custom model IDs through compat dispatch", lambda c, _: expect(c.get("profile") == "bedrock-profile" and "token" not in c and "authSchemePreference" not in c, c), {"model": {"catalog": "us.anthropic.claude-opus-4-8", "id": "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/example"}}, {"AWS_PROFILE": "bedrock-profile"})
config_case("bedrock-endpoint-resolution", "uses the generic API key option as a Bedrock bearer token", lambda c, _: expect(c.get("token") == {"token": "bedrock-api-key"} and c.get("authSchemePreference") == ["httpBearerAuth"], c), {"options": {"cacheRetention": "none", "apiKey": "bedrock-api-key"}})


def stream_case(suite, name, check, frames=None, spec=None, server=None, differential=True):
    base = {"model": {"catalog": "us.anthropic.claude-opus-4-8"}, "context": hello(), "options": {"cacheRetention": "none"}}
    case(suite, name, dict(base, **(spec or {})), check, server=server or (lambda: Server(frames=frames or [])), differential=differential)


def terminal(*items):
    return events(("messageStart", {"role": "assistant"}), *items)


# bedrock-raw-stop-reason.test.ts
def raw_check(stop, raw, error):
    def check(lines, _requests):
        m = message(lines)
        expect(m["stopReason"] == stop and m.get("rawStopReason") == raw and m.get("errorMessage") == error, m)
    return check


stream_case("bedrock-raw-stop-reason", "preserves raw Bedrock stop reasons for successful stops", raw_check("stop", "end_turn", None), terminal(("messageStop", {"stopReason": "end_turn"})))
stream_case("bedrock-raw-stop-reason", "preserves raw Bedrock stop reasons for provider error stops", raw_check("error", "guardrail_intervened", "Provider stopped with: guardrail_intervened"), terminal(("messageStop", {"stopReason": "guardrail_intervened"})))

# bedrock-response-headers.test.ts
def response_headers(lines, _requests):
    expect(message(lines)["stopReason"] == "error", message(lines))
    expect(len(lines["response"]) == 1 and lines["response"][0]["status"] == 200, lines["response"])
    headers = lines["response"][0]["headers"]
    expect(headers["x-amzn-requestid"] == REQUEST_ID and headers["x-bifrost-provider"] == "bedrock" and headers["x-bifrost-resolved-model"] == "us.anthropic.claude-opus-4-8", headers)


stream_case("bedrock-response-headers", "forwards raw Smithy response headers to onResponse", response_headers, spec={"observe": True, "options": {"cacheRetention": "none", "env": {"AWS_BEDROCK_FORCE_HTTP1": "1", "AWS_BEDROCK_SKIP_AUTH": "1"}}}, server=lambda: Server(frames=[], headers={"x-bifrost-provider": "bedrock", "x-bifrost-resolved-model": "us.anthropic.claude-opus-4-8"}))

# bedrock-cache-write-1h-cost.test.ts
def cache_1h(lines, _requests):
    usage = message(lines)["usage"]
    expect(usage["cacheWrite"] == 1_000_000 and usage["cacheWrite1h"] == 400_000, usage)
    cost = json.loads((UPSTREAM / "packages/ai/src/providers/data/amazon-bedrock.json").read_text())["bedrock-converse-stream"]["us.anthropic.claude-opus-4-8"]["cost"]
    expected = (600_000 * cost["cacheWrite"] + 400_000 * cost["input"] * 2) / 1_000_000
    expect(abs(usage["cost"]["cacheWrite"] - expected) < 1e-10, usage)


stream_case("bedrock-cache-write-1h-cost", "prices the 1h cache details at 2x while preserving the total cache write", cache_1h, terminal(("metadata", {"usage": {"inputTokens": 100, "outputTokens": 5, "totalTokens": 1_000_105, "cacheWriteInputTokens": 1_000_000, "cacheDetails": [{"ttl": "1h", "inputTokens": 150_000}, {"ttl": "5m", "inputTokens": 600_000}, {"ttl": "1h", "inputTokens": 250_000}]}}), ("messageStop", {"stopReason": "end_turn"})))


def capture_case(suite, name, check, model=None, context=None, options=None, mode="stream"):
    spec = {"model": model or {"catalog": "us.anthropic.claude-opus-4-8"}, "context": context or hello(), "options": options if options is not None else {"cacheRetention": "none"}, "abort": True, "capture": True, "mode": mode}
    case(suite, name, spec, lambda lines, requests: check(lines["payload"][0], lines, requests), server=lambda: Server(frames=[]))


def payload_fields(key, expected):
    def check(payload, _lines, _requests):
        fields = payload.get("additionalModelRequestFields") or {}
        for name, value in expected.items():
            expect(fields.get(name) == value, (name, fields))
    return check


# bedrock-thinking-payload.test.ts (the capture sets reasoning "high" unless given)
OPUS_46 = "global.anthropic.claude-opus-4-6-v1"
ADAPTIVE = {"thinking": {"type": "adaptive", "display": "summarized"}, "output_config": {"effort": "high"}, "anthropic_beta": None}
XHIGH = {"thinking": {"type": "adaptive", "display": "summarized"}, "output_config": {"effort": "xhigh"}, "anthropic_beta": None}
capture_case("bedrock-thinking-payload", "uses adaptive thinking for Claude Opus 4.8 when reasoning is enabled", payload_fields(None, ADAPTIVE), {"catalog": OPUS_46, "id": "global.anthropic.claude-opus-4-8-v1", "name": "Claude Opus 4.8 (Global)"}, options={"reasoning": "high"})
capture_case("bedrock-thinking-payload", "maps xhigh reasoning to effort=xhigh for Claude Opus 4.8", payload_fields(None, XHIGH), {"catalog": OPUS_46, "id": "global.anthropic.claude-opus-4-8-v1", "name": "Claude Opus 4.8 (Global)"}, options={"reasoning": "xhigh"})
capture_case("bedrock-thinking-payload", "uses adaptive thinking for Claude Fable 5 when reasoning is enabled", payload_fields(None, ADAPTIVE), {"catalog": "global.anthropic.claude-fable-5"}, options={"reasoning": "high"})
capture_case("bedrock-thinking-payload", "uses adaptive thinking for Claude Sonnet 5 when reasoning is enabled", payload_fields(None, ADAPTIVE), {"catalog": "global.anthropic.claude-sonnet-5"}, options={"reasoning": "high"})
capture_case("bedrock-thinking-payload", "uses adaptive thinking for Claude Opus 5 when reasoning is enabled", payload_fields(None, ADAPTIVE), {"catalog": "global.anthropic.claude-opus-5"}, options={"reasoning": "high"})
capture_case("bedrock-thinking-payload", "maps xhigh reasoning to effort=xhigh for Claude Opus 5", payload_fields(None, XHIGH), {"catalog": "global.anthropic.claude-opus-5"}, options={"reasoning": "xhigh"})
capture_case("bedrock-thinking-payload", "maps xhigh reasoning to effort=xhigh for Claude Fable 5", payload_fields(None, {"thinking": XHIGH["thinking"], "output_config": XHIGH["output_config"]}), {"catalog": "global.anthropic.claude-fable-5"}, options={"reasoning": "xhigh"})
capture_case("bedrock-thinking-payload", "omits display for GovCloud model ids on non-adaptive Claude thinking", payload_fields(None, {"thinking": {"type": "enabled", "budget_tokens": 16384}, "anthropic_beta": ["interleaved-thinking-2025-05-14"]}), {"catalog": "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "id": "us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0", "name": "Claude Sonnet 4.5 (GovCloud)"}, options={"reasoning": "high"})
capture_case("bedrock-thinking-payload", "omits display for GovCloud regions on adaptive Claude thinking", payload_fields(None, {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}, "anthropic_beta": None}), {"catalog": OPUS_46, "id": "global.anthropic.claude-opus-4-8-v1", "name": "Claude Opus 4.8 (Global)"}, options={"reasoning": "high", "region": "us-gov-west-1"})
PROFILE_ARN = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/my-profile"
capture_case("bedrock-thinking-payload", "uses adaptive thinking when model.name contains the model name but ARN does not", payload_fields(None, {"thinking": ADAPTIVE["thinking"], "output_config": ADAPTIVE["output_config"]}), {"catalog": OPUS_46, "id": PROFILE_ARN, "name": "Claude Opus 4.6"}, options={"reasoning": "high"})


def cache_points(payload, _lines, _requests):
    expect(len(payload["system"]) == 2 and "cachePoint" in payload["system"][1], payload)
    last = payload["messages"][-1]["content"][-1]
    expect("cachePoint" in last, payload)


capture_case("bedrock-thinking-payload", "injects cache points when model.name identifies a supported Claude model", cache_points, {"catalog": OPUS_46, "id": PROFILE_ARN, "name": "Claude Sonnet 4.6"}, context={"systemPrompt": "You are helpful.", "messages": [{"role": "user", "content": "Hello", "timestamp": 1}]}, options={})


def fixed_budget(payload, _lines, _requests):
    fields = payload["additionalModelRequestFields"]
    expect(fields["thinking"]["type"] == "enabled" and isinstance(fields["thinking"]["budget_tokens"], (int, float)), fields)
    expect(fields["anthropic_beta"] == ["interleaved-thinking-2025-05-14"], fields)


capture_case("bedrock-thinking-payload", "falls back to fixed-budget thinking for non-adaptive Claude via model.name", fixed_budget, {"catalog": "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "id": PROFILE_ARN, "name": "Claude Sonnet 4.5"}, options={"reasoning": "high"})

# bedrock-convert-messages.test.ts
SONNET_45 = {"catalog": "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "id": "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "name": "Claude Sonnet 4.5 (US)", "baseUrl": "https://bedrock-runtime.us-east-1.amazonaws.com", "reasoning": True, "input": ["text", "image"], "contextWindow": 200000, "maxTokens": 64000, "compat": {"supportsStrictMode": True}}
NOVA = dict(SONNET_45, id="amazon.nova-lite-v1:0", name="Nova Lite", reasoning=False, compat=None)
LOOKUP = {"type": "object", "required": ["value"], "properties": {"value": {"type": "string"}}}
USAGE0 = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 0, "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0}}


def strict_check(expected):
    def check(payload, _lines, _requests):
        spec = payload["toolConfig"]["tools"][0]["toolSpec"]
        expect(spec.get("strict") == expected, spec)
    return check


capture_case("bedrock-convert-messages", "gates native strict tool use by model capability (strict model)", strict_check(True), SONNET_45, context={"messages": [{"role": "user", "content": "Use the tool", "timestamp": 1}], "tools": [{"name": "lookup", "description": "Look up a value", "parameters": LOOKUP, "constrainedSampling": {"type": "json_schema", "strict": "require"}}]})
capture_case("bedrock-convert-messages", "gates native strict tool use by model capability (nova prefer)", strict_check(None), NOVA, context={"messages": [{"role": "user", "content": "Use the tool", "timestamp": 1}], "tools": [{"name": "lookup", "description": "Look up a value", "parameters": LOOKUP, "constrainedSampling": {"type": "json_schema", "strict": "prefer"}}]})


def empty_names(lines, _requests):
    expect(message(lines)["content"][0] == {"type": "toolCall", "id": "tool-1", "name": "edit", "arguments": {"path": "/workspace/foobar/file.js", "edits": [{"oldText": "first", "newText": "updated first"}, {"oldText": "second", "newText": "updated second", "": ""}]}}, message(lines))


stream_case("bedrock-convert-messages", "preserves empty property names in streamed tool arguments", empty_names, terminal(("contentBlockStart", {"contentBlockIndex": 0, "start": {"toolUse": {"toolUseId": "tool-1", "name": "edit"}}}), ("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"toolUse": {"input": '{"path":"/workspace/foobar/file.js","edits":[{"oldText":"first","newText":"updated first"},{"oldText":"second","newText":"updated second","":""}]}'}}}), ("contentBlockStop", {"contentBlockIndex": 0}), ("messageStop", {"stopReason": "tool_use"})), spec={"model": dict(SONNET_45, catalog="us.anthropic.claude-sonnet-4-5-20250929-v1:0")})


def user_content(expected, count=1):
    def check(payload, _lines, _requests):
        expect(len(payload["messages"]) == count, payload)
        if count:
            expect(payload["messages"][0]["content"] == expected, payload)
    return check


def assistant(content, stop="stop"):
    return {"role": "assistant", "content": content, "api": "bedrock-converse-stream", "provider": "amazon-bedrock", "model": SONNET_45["id"], "usage": USAGE0, "stopReason": stop, "timestamp": 1}


capture_case("bedrock-convert-messages", "replaces blank user string content with a placeholder", user_content([{"text": "<empty>"}]), NOVA, context={"messages": [{"role": "user", "content": "   ", "timestamp": 1}]})
capture_case("bedrock-convert-messages", "filters blank user text blocks when other content remains", user_content([{"text": "hello"}]), NOVA, context={"messages": [{"role": "user", "content": [{"type": "text", "text": ""}, {"type": "text", "text": "hello"}], "timestamp": 1}]})


def blank_result(payload, _lines, _requests):
    expect(len(payload["messages"]) == 1 and payload["messages"][0]["content"][0]["toolResult"]["content"] == [{"text": "<empty>"}], payload)


capture_case("bedrock-convert-messages", "replaces blank tool result content with a placeholder", blank_result, NOVA, context={"messages": [{"role": "toolResult", "toolCallId": "tool-1", "toolName": "tool", "content": [{"type": "text", "text": ""}], "isError": False, "timestamp": 1}]})


def replay_input(payload, _lines, _requests):
    expect(payload["messages"][0]["content"][0]["toolUse"]["input"] == {"path": "/workspace/foobar/file.js", "edits": [{"oldText": "first", "newText": "updated first"}, {"oldText": "second", "newText": "updated second"}]}, payload)


capture_case("bedrock-convert-messages", "removes empty property names only from replayed Bedrock input", replay_input, NOVA, context={"messages": [assistant([{"type": "toolCall", "id": "tool-1", "name": "edit", "arguments": {"path": "/workspace/foobar/file.js", "edits": [{"oldText": "first", "newText": "updated first"}, {"oldText": "second", "newText": "updated second", "": ""}]}}], "toolUse"), {"role": "toolResult", "toolCallId": "tool-1", "toolName": "edit", "content": [{"type": "text", "text": "done"}], "isError": False, "timestamp": 1}, {"role": "user", "content": "Continue", "timestamp": 1}]})

# bedrock-redacted-reasoning.test.ts
GPT = {"catalog": "us.anthropic.claude-opus-4-8", "id": "global.openai.gpt-5.6-terra", "name": "GPT-5.6 Terra (Global)", "reasoning": True, "input": ["text"], "contextWindow": 400000, "maxTokens": 128000, "compat": None}


def redacted_events(*extra):
    return terminal(("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"reasoningContent": {"redactedContent": REDACTED_BASE64}}}), *extra)


def not_error(lines, _requests):
    m = message(lines)
    expect(m["stopReason"] != "error" and [c["type"] for c in m["content"]] == ["thinking", "text"] and m["content"][1] == {"type": "text", "text": "done"}, m)


def preserved(lines, _requests):
    thinking = next(c for c in message(lines)["content"] if c["type"] == "thinking")
    expect(thinking.get("redacted") is True and thinking.get("thinkingSignature") == REDACTED_BASE64 and "redactedChunks" not in thinking, thinking)


def never_stopped(lines, _requests):
    thinking = next(c for c in message(lines)["content"] if c["type"] == "thinking")
    expect(thinking.get("thinkingSignature") == REDACTED_BASE64 and "redactedChunks" not in thinking and "index" not in thinking, thinking)


def joined(lines, _requests):
    thinking = next(c for c in message(lines)["content"] if c["type"] == "thinking")
    expect(thinking.get("thinkingSignature") == REDACTED_BASE64 and thinking["thinking"] == "[Reasoning redacted]", thinking)


FULL_REDACTED = redacted_events(("contentBlockStop", {"contentBlockIndex": 0}), ("contentBlockDelta", {"contentBlockIndex": 1, "delta": {"text": "done"}}), ("contentBlockStop", {"contentBlockIndex": 1}), ("messageStop", {"stopReason": "end_turn"}))
stream_case("bedrock-redacted-reasoning", "does not fail the stream when reasoning arrives as redactedContent", not_error, FULL_REDACTED, spec={"model": GPT, "options": {}})
stream_case("bedrock-redacted-reasoning", "preserves the encrypted reasoning payload on the assistant message", preserved, FULL_REDACTED, spec={"model": GPT, "options": {}})
stream_case("bedrock-redacted-reasoning", "encodes the payload when the stream never sends contentBlockStop", never_stopped, redacted_events(("messageStop", {"stopReason": "end_turn"})), spec={"model": GPT, "options": {}})
stream_case("bedrock-redacted-reasoning", "joins encrypted reasoning split across deltas", joined, terminal(("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"reasoningContent": {"redactedContent": base64.b64encode(REDACTED[:7]).decode()}}}), ("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"reasoningContent": {"redactedContent": base64.b64encode(REDACTED[7:]).decode()}}}), ("contentBlockStop", {"contentBlockIndex": 0}), ("messageStop", {"stopReason": "end_turn"})), spec={"model": GPT, "options": {}})


def replayed(expected):
    def check(payload, _lines, _requests):
        entry = next(m for m in payload["messages"] if m["role"] == "assistant")
        expect(entry["content"] == expected, entry)
    return check


GPT_ASSISTANT = lambda content, stop: dict(assistant(content, stop), model="global.openai.gpt-5.6-terra")
capture_case("bedrock-redacted-reasoning", "replays redacted reasoning as reasoningContent.redactedContent", replayed([{"reasoningContent": {"redactedContent": REDACTED_BASE64}}, {"text": "done"}]), GPT, context={"messages": [{"role": "user", "content": "hello", "timestamp": 1}, GPT_ASSISTANT([{"type": "thinking", "thinking": "", "thinkingSignature": REDACTED_BASE64, "redacted": True}, {"type": "text", "text": "done"}], "stop"), {"role": "user", "content": "continue", "timestamp": 1}]})
capture_case("bedrock-redacted-reasoning", "replays redacted reasoning before the toolUse block it belongs to", replayed([{"reasoningContent": {"redactedContent": REDACTED_BASE64}}, {"toolUse": {"toolUseId": "tool-1", "name": "read", "input": {"path": "/tmp/a.txt"}}}]), GPT, context={"messages": [{"role": "user", "content": "read the file", "timestamp": 1}, GPT_ASSISTANT([{"type": "thinking", "thinking": "", "thinkingSignature": REDACTED_BASE64, "redacted": True}, {"type": "toolCall", "id": "tool-1", "name": "read", "arguments": {"path": "/tmp/a.txt"}}], "toolUse"), {"role": "toolResult", "toolCallId": "tool-1", "toolName": "read", "content": [{"type": "text", "text": "file body"}], "isError": False, "timestamp": 1}]})

# bedrock-error-metadata.test.ts
VALIDATION_MESSAGE = "Input is too long for requested model."


def diagnostic_of(lines):
    return next((d for d in message(lines).get("diagnostics", []) if d["type"] == "bedrock_response_failure"), None)


def details(expected, stop="error"):
    def check(lines, _requests):
        expect(message(lines)["stopReason"] == stop, message(lines))
        diagnostic = diagnostic_of(lines)
        if expected is None:
            expect(diagnostic is None, diagnostic)
        else:
            expect(diagnostic is not None and diagnostic["details"] == expected and "error" not in diagnostic and sorted(diagnostic) == ["details", "timestamp", "type"], diagnostic)
    return check


def validation_server(extra=None):
    return lambda: Server(status=400, headers=dict({"x-amzn-errortype": "ValidationException:http://internal.amazon.com/coral/com.amazon.bedrock/"}, **(extra or {})), body=json.dumps({"message": VALIDATION_MESSAGE}))


stream_case("bedrock-error-metadata", "records status, error code and request id for a non-2xx from client.send()", details({"status": 400, "errorCode": "ValidationException", "requestId": REQUEST_ID}), server=validation_server())


def untouched(lines, _requests):
    expect(message(lines)["errorMessage"] == f"Validation error: {VALIDATION_MESSAGE}", message(lines))


stream_case("bedrock-error-metadata", "leaves errorMessage untouched so retry classification is unaffected", untouched, server=validation_server())
# Upstream's mock throws a bare object for a modeled exception frame; the
# pinned SDK throws the modeled ThrottlingException (checked against it), so
# its code is reported too.
stream_case("bedrock-error-metadata", "reports only the request id for a modeled mid-stream exception", details({"errorCode": "ThrottlingException", "requestId": REQUEST_ID}), [event("messageStart", {"role": "assistant"}), exception("throttlingException", {"message": "Too many requests, please wait."})])
stream_case("bedrock-error-metadata", "captures the error code for an unmodeled mid-stream error", details({"errorCode": "ModelStreamErrorException", "requestId": REQUEST_ID}), [event("messageStart", {"role": "assistant"}), error_frame("ModelStreamErrorException", "Model stream terminated unexpectedly.")])


def aborted_turn(lines, _requests):
    expect(message(lines)["stopReason"] == "aborted" and diagnostic_of(lines) is None, message(lines))


case("bedrock-error-metadata", "emits no diagnostic for an aborted turn", {"model": {"catalog": "us.anthropic.claude-opus-4-8"}, "context": hello(), "options": {"cacheRetention": "none"}, "abort": True}, aborted_turn, server=validation_server())
stream_case("bedrock-error-metadata", "drops header-derived values that exceed the length bound", details({"status": 400}), server=lambda: Server(status=400, headers={"x-amzn-errortype": "E" * 5000 + "Exception", "x-amzn-requestid": "R" * 5000}, body=json.dumps({"message": VALIDATION_MESSAGE})), differential=False)
stream_case("bedrock-error-metadata", "omits the SDK's Unknown placeholder instead of reporting it as a code", details({"status": 403, "requestId": REQUEST_ID}), server=lambda: Server(status=403, body=json.dumps({"message": "Forbidden"})))


def no_metadata(lines, _requests):
    expect(message(lines)["stopReason"] == "error" and diagnostic_of(lines) is None, message(lines))


stream_case("bedrock-error-metadata", "emits no diagnostic when the failure carries no provider metadata", no_metadata, server=lambda: Server(drop=True), differential=False)

# bedrock-custom-headers.test.ts: the build-step middleware's effect is the
# request the server receives.


def sent_header(name, value):
    def check(lines, requests):
        expect(requests[0]["headers"].get(name) == value, requests[0]["headers"])
    return check


def reserved(lines, requests):
    headers = requests[0]["headers"]
    expect(headers.get("x-allowed") == "ok", headers)
    expect(headers["authorization"].startswith("AWS4-HMAC-SHA256 ") and headers["x-amz-date"] != "evil" and headers["host"].startswith("127.0.0.1:"), headers)


def no_custom(lines, requests):
    expect("x-custom" not in requests[0]["headers"], requests[0]["headers"])


OK_FRAMES = terminal(("messageStop", {"stopReason": "end_turn"}))
stream_case("bedrock-custom-headers", "VC1: registers a build-step middleware that injects the caller header (happy path)", sent_header("x-custom", "v"), OK_FRAMES, spec={"options": {"cacheRetention": "none", "headers": {"x-custom": "v"}}})
stream_case("bedrock-custom-headers", "VC2: skips reserved headers case-insensitively while applying allowed ones", reserved, OK_FRAMES, spec={"options": {"cacheRetention": "none", "headers": {"authorization": "evil", "x-amz-date": "evil", "x-allowed": "ok", "Authorization": "evil2", "X-Amz-Date": "evil2", "HOST": "evil3"}}})
stream_case("bedrock-custom-headers", "VC3: registers no middleware when headers is undefined", no_custom, OK_FRAMES)
stream_case("bedrock-custom-headers", "VC3: registers no middleware when headers is empty", no_custom, OK_FRAMES, spec={"options": {"cacheRetention": "none", "headers": {}}})
stream_case("bedrock-custom-headers", "VC4: streamSimpleBedrock forwards headers end-to-end (regression guard)", sent_header("x-custom", "v"), OK_FRAMES, spec={"mode": "simple", "options": {"headers": {"x-custom": "v"}}})


# --- Runner ----------------------------------------------------------------

def run_case(command, backend, item, compare):
    spec = json.loads(json.dumps(item.spec))
    if item.server is None:
        env = dict(BASE_ENV, **(item.env or {}))
        lines = run(command, spec, env)
        item.check(lines["config"][0], None)
        return
    env = dict(BASE_ENV, **KEYS, **(item.env or {}))
    server = item.server()
    with server as base:
        spec["model"] = dict(spec["model"], baseUrl=base)
        lines = run(command, spec, env)
        reference = oracle(spec, env) if (compare and item.differential) else None
    item.check(lines, server.requests)
    if reference is not None:
        native, upstream = trace(lines), trace(reference)
        assert native == upstream, (item.name, json.dumps(native, indent=1)[:5000], json.dumps(upstream, indent=1)[:5000])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--only")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="bedrock-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "bedrock.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "bedrock"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            for item in CASES:
                if args.only and args.only not in item.name:
                    continue
                run_case(command, backend, item, compare=True)
                print(f"PASS {backend}: {item.suite}: {item.name}")
        # The agent runtime streams bedrock-converse-stream models through
        # this API (JavaScript lane; it compiles the whole runtime).
        output = pathlib.Path(directory) / "registered-apis.js"
        subprocess.run(["bun", args.toolchain, str(REGISTERED), "-o", str(output)], cwd=ROOT, check=True)
        registered = subprocess.run(["bun", str(output)], capture_output=True, text=True, timeout=120)
        assert registered.returncode == 0 and "PASS bedrock-converse-stream is registered as a builtin api provider" in registered.stdout, registered
        print("PASS bun: bedrock-converse-stream is registered in the agent runtime")
        # providers/amazon-bedrock.ts credential-source resolution.
        output = pathlib.Path(directory) / "amazon-bedrock-auth.js"
        subprocess.run(["bun", args.toolchain, str(AUTH), "-o", str(output)], cwd=ROOT, check=True)
        auth = subprocess.run(["bun", str(output)], capture_output=True, text=True, timeout=120)
        assert auth.returncode == 0, auth
        for line in auth.stdout.splitlines():
            print(f"{line.split(' ', 1)[0]} bun: amazon-bedrock auth: {line.split(' ', 1)[1]}")


if __name__ == "__main__":
    main()
