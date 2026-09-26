#!/usr/bin/env python3
"""The upstream Mistral suites over the native mistral-conversations API.

mistral-http-transport, mistral-raw-stop-reason, mistral-reasoning-mode and
mistral-tool-schema: each named case runs packages/ai/test/mistral.bend
against a loopback server that answers as the upstream test's fetch stub
does (same bodies, byte-wise chunks, a stalled body, an error status),
asserts the upstream expectations, and compares the payload onPayload saw,
the onResponse value, every event and the final message with upstream
mistral-conversations.ts against the same server
(packages/ai/test/mistral-oracle.ts). Only timestamps are normalized, and
the header values Node's fetch adds on its own are ignored. Upstream's
request URL assertion (https://api.mistral.ai/v1/chat/completions) becomes
the loopback path /v1/chat/completions.
"""
from upstream_pin import UPSTREAM
import argparse
import http.server
import json
import os
import pathlib
import platform
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/ai/test/mistral.bend"
ORACLE = ROOT / "packages/ai/test/mistral-oracle.ts"
REGISTERED = ROOT / "packages/coding-agent/test/registered-apis.bend"
UNREACHABLE = "http://127.0.0.1:9"


def pi_user_agent():
    # upstream `pi (${platform()} ${release()}; ${arch()})` in Node's terms.
    arch = {"x86_64": "x64", "aarch64": "arm64"}.get(platform.machine(), platform.machine())
    return f"pi ({platform.system().lower()} {platform.release()}; {arch})"


def terminal_event(finish_reason="stop"):
    return {
        "id": "mistral-response-id",
        "model": "mistral-large-latest",
        "choices": [{"index": 0, "finish_reason": finish_reason, "delta": {}}],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
    }


def sse_body(events):
    # upstream createSseResponse.
    return "\r\n\r\n".join(f"data: {json.dumps(event, separators=(',', ':'))}" for event in events) + "\r\n\r\ndata: [DONE]\r\n\r\n"


class Server:
    """Answers every POST with one scripted response."""

    def __init__(self, body=b"", status=200, reason=None, headers=None, chunks=None, stall=False):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                outer.requests.append({"url": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(raw) if raw else None})
                self.send_response(status, reason)
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                if stall or chunks is not None:
                    self.send_header("transfer-encoding", "chunked")
                    self.end_headers()
                    self.wfile.flush()
                    if stall:
                        time.sleep(3)
                        return
                    for piece in chunks:
                        self.wfile.write(f"{len(piece):x}\r\n".encode() + piece + b"\r\n")
                        self.wfile.flush()
                    self.wfile.write(b"0\r\n\r\n")
                    return
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

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


def parse(output):
    lines = {"event": [], "payload": [], "response": [], "result": [], "thrown": []}
    for line in output.splitlines():
        kind, _, rest = line.partition(" ")
        lines[kind].append(rest if kind == "thrown" else json.loads(rest))
    return lines


def run(command, mode, base):
    result = subprocess.run([*command, mode, base], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise AssertionError((command, mode, result.returncode, result.stdout, result.stderr))
    return parse(result.stdout)


def oracle(mode, base):
    result = subprocess.run(["node", str(ORACLE), mode, base], capture_output=True, text=True, timeout=60, env=dict(os.environ, PI_MONO=str(UPSTREAM)))
    if result.returncode != 0:
        raise AssertionError(("oracle", mode, result.stdout, result.stderr))
    return parse(result.stdout)


EVENT_KEYS = {
    "start": {"type", "partial"},
    "text_start": {"type", "contentIndex", "partial"},
    "text_delta": {"type", "contentIndex", "delta", "partial"},
    "text_end": {"type", "contentIndex", "content", "partial"},
    "thinking_start": {"type", "contentIndex", "partial"},
    "thinking_delta": {"type", "contentIndex", "delta", "partial"},
    "thinking_end": {"type", "contentIndex", "content", "partial"},
    "toolcall_start": {"type", "contentIndex", "partial"},
    "toolcall_delta": {"type", "contentIndex", "delta", "partial"},
    "toolcall_end": {"type", "contentIndex", "toolCall", "partial"},
    "done": {"type", "reason", "message"},
    "error": {"type", "reason", "error"},
}


def normalized(value, typed=False):
    if isinstance(value, dict):
        keys = EVENT_KEYS.get(value.get("type"), value.keys()) if typed else value.keys()
        return {k: ("<time>" if k == "timestamp" else normalized(v)) for k, v in value.items() if k in keys}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    return value


# Node's fetch adds these response headers' siblings and its own request
# headers; the compared response headers are the server's.
def response_view(value):
    return {"status": value["status"], "headers": {k: v for k, v in value["headers"].items() if k not in ("date", "server", "transfer-encoding", "content-length", "connection", "keep-alive")}}


def trace(lines):
    return {
        "payload": lines["payload"],
        "response": [response_view(r) for r in lines["response"]],
        "events": [normalized(e, True) for e in lines["event"]],
        "result": [normalized(r) for r in lines["result"]],
        "thrown": lines["thrown"],
    }


def compare(mode, lines, reference, name):
    native, upstream = trace(lines), trace(reference)
    if mode == "timeout":
        # A 5 ms deadline may expire before or after the response head; only
        # the latter pushes `start`.
        for value in (native, upstream):
            value["events"] = [event for event in value["events"] if event["type"] != "start"]
    assert native == upstream, (name, mode, json.dumps(native, indent=1)[:6000], json.dumps(upstream, indent=1)[:6000])


def served(command, mode, server):
    with server as base:
        lines = run(command, mode, base)
        reference = oracle(mode, base)
    return lines, reference


def result(lines):
    return lines["result"][0]


# mistral-http-transport.test.ts
# ------------------------------

def case_sdk_payload(command):
    server = Server(body=sse_body([terminal_event()]).encode(), headers={"content-type": "text/event-stream", "x-request-id": "request-1"})
    lines, reference = served(command, "sdk-payload", server)
    message = result(lines)
    assert message["stopReason"] == "stop"
    request = server.requests[0]
    assert request["url"] == "/v1/chat/completions"
    headers = request["headers"]
    assert headers["authorization"] == "Bearer secret"
    assert headers["accept"] == "text/event-stream"
    assert headers["x-affinity"] == "session-1"
    assert headers["x-custom"] == "value"
    assert headers["user-agent"] == pi_user_agent(), headers
    payload = lines["payload"][0]
    assert payload["maxTokens"] == 123 and payload["promptMode"] == "reasoning" and payload["promptCacheKey"] == "session-1"
    response = lines["response"][0]
    assert response["status"] == 200
    assert {k: v for k, v in response["headers"].items() if k in ("content-type", "x-request-id")} == {"content-type": "text/event-stream", "x-request-id": "request-1"}
    wire = request["body"]
    assert wire["max_tokens"] == 123 and wire["prompt_mode"] == "reasoning" and wire["reasoning_effort"] == "high"
    assert wire["tool_choice"] == {"type": "function", "function": {"name": "lookup"}}
    assert wire["prompt_cache_key"] == "session-1"
    assert wire["top_p"] == 0.9 and wire["random_seed"] == 42 and wire["presence_penalty"] == 0.1
    assert wire["frequency_penalty"] == 0.2 and wire["parallel_tool_calls"] is True and wire["safe_prompt"] is True
    assert wire["response_format"] == {"type": "json_schema", "json_schema": {"name": "result", "schema": {"type": "object", "properties": {"maxTokens": {"type": "number"}}}}}
    for key in ("maxTokens", "promptMode", "promptCacheKey"):
        assert key not in wire
    assert wire["messages"] == [
        {"role": "system", "content": "Be precise"},
        {"role": "user", "content": [{"type": "text", "text": "describe"}, {"type": "image_url", "image_url": "data:image/png;base64,aGVsbG8="}]},
    ], wire["messages"]
    assert json.dumps(server.requests[0]["body"]) == json.dumps(server.requests[1]["body"]), (server.requests[0]["body"], server.requests[1]["body"])
    return lines, reference


def case_replay(command):
    server = Server(body=sse_body([terminal_event()]).encode(), headers={"content-type": "text/event-stream"})
    lines, reference = served(command, "replay", server)
    assert result(lines)["stopReason"] == "stop"
    assert server.requests[0]["body"]["messages"] == [
        {
            "role": "assistant",
            "prefix": False,
            "content": [{"type": "thinking", "thinking": [{"type": "text", "text": "reason"}]}, {"type": "text", "text": "answer"}],
            "tool_calls": [{"id": "abc123456", "type": "function", "function": {"name": "lookup", "arguments": '{"query":"pi"}'}, "index": 0}],
        },
        {"role": "tool", "tool_call_id": "abc123456", "name": "lookup", "content": [{"type": "text", "text": "found"}, {"type": "image_url", "image_url": "data:image/png;base64,aGVsbG8="}]},
    ], server.requests[0]["body"]["messages"]
    assert json.dumps(server.requests[0]["body"]) == json.dumps(server.requests[1]["body"])
    return lines, reference


def case_native_events(command):
    choice = lambda reason, delta: [{"index": 0, "finish_reason": reason, "delta": delta}]
    events = [
        {"id": "response-1", "model": "mistral-large-latest", "choices": choice(None, {"content": [{"type": "thinking", "thinking": [{"type": "text", "text": "reason"}]}]})},
        {"id": "response-1", "model": "mistral-large-latest", "choices": choice(None, {"content": [{"type": "text", "text": "answer"}]})},
        {"id": "response-1", "model": "mistral-large-latest", "choices": choice(None, {"tool_calls": [{"id": "abc123456", "index": 0, "function": {"name": "lookup", "arguments": '{"query":'}}]})},
        {
            "id": "response-1",
            "model": "mistral-large-latest",
            "choices": choice("tool_calls", {"tool_calls": [{"index": 0, "function": {"name": "", "arguments": '"pi"}'}}]}),
            "usage": {"prompt_tokens": 10, "completion_tokens": 4, "total_tokens": 14, "prompt_tokens_details": {"cached_tokens": 3}},
        },
    ]
    lines, reference = served(command, "native-events", Server(body=sse_body(events).encode(), headers={"content-type": "text/event-stream"}))
    message = result(lines)
    assert message["stopReason"] == "toolUse" and message["rawStopReason"] == "tool_calls" and message["responseId"] == "response-1"
    assert message["content"] == [
        {"type": "thinking", "thinking": "reason"},
        {"type": "text", "text": "answer"},
        {"type": "toolCall", "id": "abc123456", "name": "lookup", "arguments": {"query": "pi"}},
    ], message["content"]
    usage = message["usage"]
    assert (usage["input"], usage["output"], usage["cacheRead"], usage["cacheWrite"], usage["totalTokens"]) == (7, 4, 3, 0, 14)
    return lines, reference


def case_bytewise(command):
    event = {"id": "response-bytewise", "model": "mistral-large-latest", "choices": [{"index": 0, "finish_reason": "stop", "delta": {"content": "héllo 🌍"}}], "usage": {"prompt_tokens": 1, "completion_tokens": 2, "total_tokens": 3}}
    data = f"data: {json.dumps(event, ensure_ascii=False, separators=(',', ':'))}\r\n\r\ndata: [DONE]\r\n\r\n".encode()
    lines, reference = served(command, "bytewise", Server(chunks=[bytes([b]) for b in data], headers={"content-type": "text/event-stream"}))
    message = result(lines)
    assert message["stopReason"] == "stop"
    assert message["content"] == [{"type": "text", "text": "héllo 🌍"}], message["content"]
    return lines, reference


def case_header_overrides(command):
    server = Server(body=sse_body([terminal_event()]).encode(), headers={"content-type": "text/event-stream"})
    lines, reference = served(command, "header-overrides", server)
    headers = server.requests[0]["headers"]
    assert "authorization" not in headers and "x-affinity" not in headers
    assert headers["user-agent"] == "custom-agent"
    assert server.requests[0]["headers"].keys() - {"host", "connection", "accept-encoding", "accept-language", "sec-fetch-mode", "content-length"} == server.requests[1]["headers"].keys() - {"host", "connection", "accept-encoding", "accept-language", "sec-fetch-mode", "content-length"}
    return lines, reference


def case_abort(command):
    lines, reference = served(command, "abort", Server(stall=True, headers={"content-type": "text/event-stream"}))
    assert result(lines)["stopReason"] == "aborted", result(lines)
    return lines, reference


def case_timeout(command):
    lines, reference = served(command, "timeout", Server(stall=True, headers={"content-type": "text/event-stream"}))
    message = result(lines)
    assert message["stopReason"] == "error"
    assert "timeout" in message["errorMessage"].lower(), message
    return lines, reference


def case_http_error(command):
    lines, reference = served(command, "http-error", Server(body=b'{"message":"blocked by gateway"}', status=403, reason="Forbidden"))
    message = result(lines)
    assert message["stopReason"] == "error"
    assert message["errorMessage"] == 'Mistral API error (403): {"message":"blocked by gateway"}'
    return lines, reference


# mistral-raw-stop-reason.test.ts
# -------------------------------

def raw_body(reason):
    event = {"id": "mistral-response-id", "model": "devstral-medium-latest", "choices": [{"index": 0, "finish_reason": reason, "delta": {}}], "usage": {"prompt_tokens": 1, "completion_tokens": 0, "total_tokens": 1}}
    return f"data: {json.dumps(event)}\n\ndata: [DONE]\n\n".encode()


def raw_case(mode, reason, stop, error):
    def case(command):
        lines, reference = served(command, mode, Server(body=raw_body(reason), headers={"content-type": "text/event-stream"}))
        message = result(lines)
        assert message["stopReason"] == stop and message["rawStopReason"] == reason
        assert message.get("errorMessage") == error, message
        return lines, reference
    return case


# mistral-reasoning-mode.test.ts / mistral-tool-schema.test.ts
# ------------------------------------------------------------

def payload_case(mode, check):
    def case(command):
        lines = run(command, mode, UNREACHABLE)
        reference = oracle(mode, UNREACHABLE)
        assert lines["payload"], "Expected payload to be captured before request failure"
        check(lines["payload"][0], result(lines))
        return lines, reference
    return case


def effort(expected):
    def check(payload, _message):
        assert payload.get("reasoningEffort") == expected and "promptMode" not in payload, payload
    return check


def no_reasoning(payload, _message):
    assert "reasoningEffort" not in payload and "promptMode" not in payload, payload


def prompt_mode(payload, _message):
    assert payload.get("promptMode") == "reasoning" and "reasoningEffort" not in payload, payload


def tool_schema(payload, message):
    tools = payload.get("tools")
    assert tools and len(tools) == 1 and tools[0]["function"]["strict"] is True, payload
    parameters = tools[0]["function"]["parameters"]
    assert parameters["properties"]["nested"], parameters
    assert message["stopReason"] == "error" and "Input validation failed" not in message["errorMessage"]


CASES = [
    ("serializes SDK-style payloads to the Mistral wire format", "sdk-payload", case_sdk_payload),
    ("serializes assistant thinking, tool calls, and tool results for replay", "replay", case_replay),
    ("parses native thinking, text, fragmented tool calls, and cached-token usage", "native-events", case_native_events),
    ("parses SSE and UTF-8 sequences split across transport chunks", "bytewise", case_bytewise),
    ("honors case-insensitive header overrides and explicit affinity suppression", "header-overrides", case_header_overrides),
    ("aborts while waiting for an SSE chunk", "abort", case_abort),
    ("applies the request timeout while waiting for an SSE chunk", "timeout", case_timeout),
    ("preserves HTTP status and response bodies in errors", "http-error", case_http_error),
    ("preserves raw Mistral finish reasons for successful stops", "raw-stop", raw_case("raw-stop", "stop", "stop", None)),
    ("preserves raw Mistral finish reasons for provider error stops", "raw-error", raw_case("raw-error", "error", "error", "Provider stopped with: error")),
    ("treats unknown Mistral finish reasons as provider error stops", "raw-unmapped", raw_case("raw-unmapped", "unmapped_error", "error", "Provider stopped with: unmapped_error")),
    ("uses reasoning_effort for Mistral Small 4", "reasoning-small-medium", payload_case("reasoning-small-medium", effort("high"))),
    ("omits reasoning controls for Mistral Small 4 when thinking is off", "reasoning-small-off", payload_case("reasoning-small-off", no_reasoning)),
    ("uses prompt_mode for Magistral reasoning models", "reasoning-magistral", payload_case("reasoning-magistral", prompt_mode)),
    ("zai-glm-5-2 uses reasoning_effort when thinking is enabled", "reasoning-glm-on", payload_case("reasoning-glm-on", effort("high"))),
    ("zai-glm-5-2 omits reasoning controls when thinking is off", "reasoning-glm-off", payload_case("reasoning-glm-off", no_reasoning)),
    ("mistral-medium-2604 uses reasoning_effort when thinking is enabled", "reasoning-medium-2604-on", payload_case("reasoning-medium-2604-on", effort("high"))),
    ("mistral-medium-2604 omits reasoning controls when thinking is off", "reasoning-medium-2604-off", payload_case("reasoning-medium-2604-off", no_reasoning)),
    ("mistral-medium-latest uses reasoning_effort when thinking is enabled", "reasoning-medium-latest-on", payload_case("reasoning-medium-latest-on", effort("high"))),
    ("mistral-medium-latest omits reasoning controls when thinking is off", "reasoning-medium-latest-off", payload_case("reasoning-medium-latest-off", no_reasoning)),
    ("omits reasoning controls for non-reasoning Medium models", "reasoning-medium-2505", payload_case("reasoning-medium-2505", no_reasoning)),
    ("uses the session id as prompt cache key", "cache-key", payload_case("cache-key", lambda payload, _m: payload.get("promptCacheKey") == "session-123" or (_ for _ in ()).throw(AssertionError(payload)))),
    ("omits prompt cache key when cache retention is disabled", "cache-none", payload_case("cache-none", lambda payload, _m: "promptCacheKey" not in payload or (_ for _ in ()).throw(AssertionError(payload)))),
    ("strips TypeBox symbol keys before the SDK validates tool schemas", "tool-schema", payload_case("tool-schema", tool_schema)),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--only")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="mistral-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "mistral.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "mistral"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            for name, mode, case in CASES:
                if args.only and args.only != mode:
                    continue
                lines, reference = case(command)
                compare(mode, lines, reference, name)
                print(f"PASS {backend}: {name} (matches upstream trace)")
        # The agent runtime streams mistral-conversations models through this
        # API (JavaScript lane; it compiles the whole runtime).
        output = pathlib.Path(directory) / "registered-apis.js"
        subprocess.run(["bun", args.toolchain, str(REGISTERED), "-o", str(output)], cwd=ROOT, check=True)
        registered = subprocess.run(["bun", str(output)], capture_output=True, text=True, timeout=120)
        assert registered.returncode == 0 and "PASS mistral-conversations is registered as a builtin api provider" in registered.stdout, registered
        print("PASS bun: mistral-conversations is registered in the agent runtime")


if __name__ == "__main__":
    main()
