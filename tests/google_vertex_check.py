#!/usr/bin/env python3
"""The upstream Google Vertex suites over the native google-vertex API.

google-vertex-api-key-resolution, and the Vertex rows of google-raw-stop-reason
and google-thinking-level-map: each case runs packages/ai/test/google-vertex.bend
against a loopback server that serves the OAuth2 token endpoint and the
streamGenerateContent endpoint. Upstream's suites mock the GoogleGenAI
constructor; the client configuration cases assert the constructor options
the native client computes, and the streamed cases compare the payload,
events, final message and the requests the server received with upstream
google-vertex.ts driving the pinned @google/genai SDK and
google-auth-library against the same server (packages/ai/test/google-vertex-oracle.ts).
Application Default Credentials come from an authorized_user credentials
file; the token endpoint is the server's.
"""
from upstream_pin import UPSTREAM
import argparse
import http.server
import json
import os
import pathlib
import platform
import re
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/ai/test/google-vertex.bend"
ORACLE = ROOT / "packages/ai/test/google-vertex-oracle.ts"
AUTH = ROOT / "packages/ai/test/google-vertex-auth.bend"
REGISTERED = ROOT / "packages/coding-agent/test/registered-apis.bend"
AGENT = "pi-bend-test"
KEY = "AIzaSyExampleRealisticLookingApiKey123456"
COMPARED_HEADERS = ("authorization", "content-type", "x-goog-api-key", "x-goog-user-project", "x-custom", "user-agent")
ADC_FILE = {"type": "authorized_user", "client_id": "client-id.apps.googleusercontent.com", "client_secret": "client-secret", "refresh_token": "refresh-token", "quota_project_id": "quota-project"}


def sse(*chunks):
    return "".join("data: " + json.dumps(chunk, separators=(",", ":")) + "\r\n\r\n" for chunk in chunks)


class Server:
    """Serves /token and answers the model request with a scripted response."""

    def __init__(self, body="", status=200, token_status=200):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                token = self.path == "/token"
                outer.requests.append({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": raw if token else (json.loads(raw) if raw else None)})
                if token:
                    data = json.dumps({"access_token": "ya29.test-token", "expires_in": 3599, "token_type": "Bearer"} if token_status == 200 else {"error": "invalid_grant", "error_description": "Bad Request"}).encode()
                    self.send_response(token_status)
                    self.send_header("content-type", "application/json")
                else:
                    data = body.encode()
                    self.send_response(status)
                    self.send_header("content-type", "text/event-stream" if status == 200 else "application/json")
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


def parse(output):
    lines = {"event": [], "payload": [], "response": [], "result": [], "config": [], "thrown": []}
    for line in output.splitlines():
        kind, _, rest = line.partition(" ")
        if kind == "thrown":
            lines[kind].append(rest)
        elif kind in lines:
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


GENERATED = re.compile(r"^(.*)_\d+_(\d+)$")


def normalized(value):
    # Generated tool call ids embed Date.now(); timestamps differ; events
    # carry live partials upstream and snapshots natively.
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            if key in ("timestamp", "partial"):
                continue
            if key == "id" and isinstance(item, str) and GENERATED.match(item):
                item = GENERATED.sub(r"\1_<now>_\2", item)
            out[key] = normalized(item)
        return out
    if isinstance(value, list):
        return [normalized(item) for item in value]
    return value


def payloads(lines):
    # upstream's params carry config.abortSignal, which JSON renders as {}.
    return [{**p, "config": {k: v for k, v in p.get("config", {}).items() if k != "abortSignal"}} if isinstance(p, dict) else p for p in lines["payload"]]


def trace(lines, requests):
    return {
        "payload": payloads(lines),
        "events": [normalized(e) for e in lines["event"]],
        "result": [normalized(r) for r in lines["result"]],
        "thrown": lines["thrown"],
        "requests": [{"path": r["path"], "body": r["body"], "headers": {k: r["headers"].get(k) for k in COMPARED_HEADERS if not (k == "user-agent" and r["path"] == "/token")}} for r in requests],
    }


def message(lines):
    assert len(lines["result"]) == 1, lines
    return lines["result"][0]


# Cases
# -----

CASES = []


def case(suite, name, spec, check, body="", status=200, token_status=200, env=None, differential=True):
    CASES.append({"suite": suite, "name": name, "spec": spec, "check": check, "body": body, "status": status, "token_status": token_status, "env": env or {}, "differential": differential})


def config_case(name, spec, check, env=None):
    case("google-vertex-api-key-resolution", name, {**spec, "mode": "config"}, check, env=env, differential=False)


def config_of(lines):
    assert len(lines["config"]) == 1, lines
    return lines["config"][0]


def adc(project="test-project", location="us-central1"):
    return lambda lines, _: (lambda c: None if c["vertexai"] and c["project"] == project and c["location"] == location and c["apiVersion"] == "v1" and "apiKey" not in c else fail(c))(config_of(lines))


def fail(value):
    raise AssertionError(value)


def expect(ok, value):
    if not ok:
        raise AssertionError(value)


PROJECT = {"project": "test-project", "location": "us-central1"}
config_case("falls back to ADC when options.apiKey is a placeholder marker", {"options": {"apiKey": "<authenticated>", **PROJECT}}, adc())
config_case("falls back to ADC when options.apiKey is the gcp-vertex-credentials marker", {"options": {"apiKey": "gcp-vertex-credentials", **PROJECT}}, adc())
config_case("falls back to ADC when GOOGLE_CLOUD_API_KEY is a placeholder marker", {"options": PROJECT}, adc(), env={"GOOGLE_CLOUD_API_KEY": "<authenticated>"})
config_case("still uses the API key client for real API keys", {"options": {"apiKey": KEY}}, lambda lines, _: (lambda c: expect(c.get("apiKey") == KEY and c["apiVersion"] == "v1" and "project" not in c and "location" not in c, c))(config_of(lines)))
config_case("does not forward generated Vertex base URL placeholders", {"options": PROJECT}, lambda lines, _: expect(config_of(lines)["httpOptions"] == {"headers": {"User-Agent": AGENT}}, lines))
config_case("lets explicit headers override the default User-Agent", {"options": {**PROJECT, "headers": {"User-Agent": "custom-agent"}}}, lambda lines, _: expect(config_of(lines)["httpOptions"] == {"headers": {"User-Agent": "custom-agent"}}, lines))
config_case("forwards custom baseUrl to the ADC client", {"model": {"baseUrl": "https://proxy.example.com"}, "options": PROJECT}, lambda lines, _: (lambda c: expect(c["project"] == "test-project" and c["httpOptions"]["baseUrl"] == "https://proxy.example.com" and c["httpOptions"]["baseUrlResourceScope"] == "COLLECTION", c))(config_of(lines)))
config_case("forwards custom baseUrl to the API key client", {"model": {"baseUrl": "https://proxy.example.com"}, "options": {"apiKey": KEY}}, lambda lines, _: (lambda c: expect(c["apiKey"] == KEY and c["httpOptions"]["baseUrl"] == "https://proxy.example.com" and c["httpOptions"]["baseUrlResourceScope"] == "COLLECTION" and "apiVersion" not in c["httpOptions"], c))(config_of(lines)))
config_case("does not append apiVersion when custom baseUrl already includes one", {"model": {"baseUrl": "https://proxy.example.com/v1/projects/test-project/locations/global"}, "options": PROJECT}, lambda lines, _: expect({k: config_of(lines)["httpOptions"][k] for k in ("baseUrl", "baseUrlResourceScope", "apiVersion")} == {"baseUrl": "https://proxy.example.com/v1/projects/test-project/locations/global", "baseUrlResourceScope": "COLLECTION", "apiVersion": ""}, lines))
config_case("project and location come from the environment", {"options": {}}, adc("env-project", "europe-west4"), env={"GCLOUD_PROJECT": "env-project", "GOOGLE_CLOUD_LOCATION": "europe-west4"})
config_case("a missing project is an error", {"options": {"location": "us-central1"}}, lambda lines, _: expect(lines["thrown"] == ["Vertex AI requires a project ID. Set GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT or pass project in options."], lines))
config_case("a missing location is an error", {"options": {"project": "p"}}, lambda lines, _: expect(lines["thrown"] == ["Vertex AI requires a location. Set GOOGLE_CLOUD_LOCATION or pass location in options."], lines))

HELLO = {"messages": [{"role": "user", "content": "hello", "timestamp": 1}]}


def chunk(finish, call=False):
    candidate = {"finishReason": finish}
    if call:
        candidate["content"] = {"parts": [{"functionCall": {"id": "call-1", "name": "echo", "args": {"value": "truncated"}}}]}
    return sse({"responseId": "google-response-id", "candidates": [candidate], "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 0, "totalTokenCount": 1}})


def stopped(stop, raw, error=None, call=None):
    def check(lines, requests):
        m = message(lines)
        expect(m["stopReason"] == stop and m.get("rawStopReason") == raw, m)
        if error is not None:
            expect(m.get("errorMessage") == error, m)
        if call is not None:
            expect(any(b["type"] == "toolCall" for b in m["content"]) == call, m)
    return check


def adc_stream(extra=None):
    return {"model": {"baseUrl": "{base}"}, "context": HELLO, "options": PROJECT, **(extra or {})}


case("google-raw-stop-reason", "preserves raw Gemini finish reasons for Google Vertex errors", adc_stream(), stopped("error", "SAFETY", "Provider stopped with: SAFETY"), body=chunk("SAFETY"))
case("google-raw-stop-reason", "preserves MAX_TOKENS with a tool call as length for Google Vertex", adc_stream(), stopped("length", "MAX_TOKENS", call=True), body=chunk("MAX_TOKENS", True))
case("google-raw-stop-reason", "maps STOP with a tool call to toolUse for Google Vertex", adc_stream(), stopped("toolUse", "STOP", call=True), body=chunk("STOP", True))


def vertex_model(model_id, levels):
    return {"id": model_id, "name": model_id, "provider": "test-vertex", "baseUrl": "https://example.invalid/v1", "reasoning": True, "thinkingLevelMap": levels, "input": ["text"], "contextWindow": 128000, "maxTokens": 4096}


def thinking(expected, exact=True):
    def check(lines, _):
        expect(len(lines["payload"]) == 1 and "payload captured" in (message(lines).get("errorMessage") or ""), lines)
        got = lines["payload"][0]["config"].get("thinkingConfig")
        expect(got == expected if exact else all(got.get(k) == v for k, v in expected.items()), got)
    return check


def captured(model, reasoning=None, budgets=None):
    options = {"apiKey": "test"}
    if reasoning:
        options["reasoning"] = reasoning
    if budgets:
        options["thinkingBudgets"] = budgets
    return {"mode": "simple", "model": model, "context": {"messages": [{"role": "user", "content": "Hello", "timestamp": 0}]}, "options": options, "capture": True, "throwPayload": True}


LEVELS = {"off": None, "minimal": None, "low": "low", "medium": "medium", "high": "high", "xhigh": None, "max": None}
case("google-thinking-level-map", "uses the lowest supported Google Vertex level when reasoning is omitted", captured(vertex_model("gemini-3.8-flash", LEVELS)), thinking({"thinkingLevel": "LOW"}))
case("google-thinking-level-map", "preserves native medium effort for Gemini 3.1 Pro on Google Vertex", captured(vertex_model("gemini-3.1-pro-preview", LEVELS), "medium"), thinking({"includeThoughts": True, "thinkingLevel": "MEDIUM"}))
case("google-thinking-level-map", "disables Gemini 2.5 thinking when reasoning is omitted on Google Vertex", captured(vertex_model("gemini-2.5-flash", {})), thinking({"thinkingBudget": 0}))
case("google-thinking-level-map", "maps Google Vertex extended levels", captured(vertex_model("gemini-3.7-flash", {"xhigh": "high"}), "xhigh"), thinking({"includeThoughts": True, "thinkingLevel": "HIGH"}, False))
case("google-thinking-level-map", "uses mapped Google Vertex levels for token budgets", captured(vertex_model("gemini-2.5-flash", {"max": "high"}), "max", {"high": 4321}), thinking({"thinkingBudget": 4321}, False))
case("native", "Gemini 2.5 Flash-Lite takes the 2.5 Flash minimal budget on Google Vertex", captured(vertex_model("gemini-2.5-flash-lite", {}), "minimal"), thinking({"includeThoughts": True, "thinkingBudget": 128}))

TOOLS = {"systemPrompt": "Be brief.", "tools": [{"name": "lookup", "description": "Look up a value", "parameters": {"type": "object", "properties": {"value": {"type": "string"}}, "required": ["value"]}}],
         "messages": [{"role": "user", "content": [{"type": "text", "text": "Use the tool"}, {"type": "image", "data": "aGVsbG8=", "mimeType": "image/png"}], "timestamp": 1},
                      {"role": "assistant", "content": [{"type": "thinking", "thinking": "reasoning", "thinkingSignature": "AAAAAAAAAAAAAAAAAAAAAA=="}, {"type": "toolCall", "id": "call-1", "name": "lookup", "arguments": {"value": "42"}, "thoughtSignature": "AAAAAAAAAAAAAAAAAAAAAA=="}], "api": "google-vertex", "provider": "google-vertex", "model": "gemini-3-flash-preview", "usage": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 0, "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0}}, "stopReason": "toolUse", "timestamp": 2},
                      {"role": "toolResult", "toolCallId": "call-1", "toolName": "lookup", "content": [{"type": "text", "text": "found"}], "isError": False, "timestamp": 3}, {"role": "user", "content": "Thanks", "timestamp": 4}]}
TEXT = sse({"candidates": [{"content": {"parts": [{"text": "Why", "thought": True, "thoughtSignature": "c2ln"}], "role": "model"}}], "responseId": "r1"},
           {"candidates": [{"content": {"parts": [{"text": "Hel"}], "role": "model"}}]},
           {"candidates": [{"content": {"parts": [{"text": "lo"}, {"functionCall": {"name": "lookup", "args": {"value": "x"}}}], "role": "model"}, "finishReason": "STOP"}],
            "usageMetadata": {"promptTokenCount": 120, "cachedContentTokenCount": 20, "candidatesTokenCount": 30, "thoughtsTokenCount": 7, "totalTokenCount": 157}})


def ok_text(lines, requests):
    m = message(lines)
    expect(m["stopReason"] == "toolUse" and m["api"] == "google-vertex" and m.get("responseId") == "r1", m)


def api_key_request(lines, requests):
    ok_text(lines, requests)
    expect(len(requests) == 1 and requests[0]["path"] == "/v1/publishers/google/models/gemini-3-flash-preview:streamGenerateContent?alt=sse" and requests[0]["headers"].get("x-goog-api-key") == KEY and "authorization" not in requests[0]["headers"], requests)


def adc_request(lines, requests):
    ok_text(lines, requests)
    expect([r["path"] for r in requests] == ["/token", "/v1/publishers/google/models/gemini-3-flash-preview:streamGenerateContent?alt=sse"], requests)
    expect(requests[1]["headers"].get("authorization") == "Bearer ya29.test-token" and requests[1]["headers"].get("x-goog-user-project") == "quota-project", requests)
    expect("grant_type=refresh_token" in requests[0]["body"] and "refresh_token=refresh-token" in requests[0]["body"], requests)


case("native", "an API key request with tools, images and a replayed tool call", {"model": {"baseUrl": "{base}"}, "context": TOOLS, "options": {"apiKey": KEY, "toolChoice": "any", "temperature": 0.5, "maxTokens": 100, "thinking": {"enabled": True, "level": "HIGH"}, "headers": {"x-custom": "value"}}, "capture": True}, api_key_request, body=TEXT)
case("native", "an ADC request refreshes the authorized_user token first", adc_stream({"context": TOOLS, "capture": True}), adc_request, body=TEXT)
case("native", "streamSimple over ADC", {**adc_stream({"context": TOOLS}), "mode": "simple", "options": {"reasoning": "low"}}, adc_request, body=TEXT, env={"GOOGLE_CLOUD_PROJECT": "test-project", "GOOGLE_CLOUD_LOCATION": "us-central1"})
case("native", "an HTTP error status is the error message", {"model": {"baseUrl": "{base}"}, "context": HELLO, "options": {"apiKey": KEY}}, lambda lines, _: expect(message(lines)["stopReason"] == "error" and "Invalid argument" in message(lines)["errorMessage"], lines),
     body=json.dumps({"error": {"code": 400, "message": "Invalid argument", "status": "INVALID_ARGUMENT"}}), status=400)
case("native", "a rejected token refresh is the error message", adc_stream(), lambda lines, _: expect(message(lines)["stopReason"] == "error" and message(lines)["errorMessage"] == "invalid_grant", lines), token_status=400)
case("native", "a stream without a finish reason names Google Vertex", {"model": {"baseUrl": "{base}"}, "context": HELLO, "options": {"apiKey": KEY}}, lambda lines, _: expect(message(lines)["errorMessage"] == "Google Vertex stream ended without a finish reason", lines), body=sse({"candidates": [{"content": {"parts": [{"text": "a"}], "role": "model"}}]}))


def filled(value, base, token):
    if isinstance(value, dict):
        return {k: filled(v, base, token) for k, v in value.items()}
    if isinstance(value, list):
        return [filled(v, base, token) for v in value]
    return base if value == "{base}" else value


def run_case(command, item, directory, compare):
    credentials = pathlib.Path(directory) / "adc.json"
    credentials.write_text(json.dumps(ADC_FILE))
    home = pathlib.Path(directory) / "home"
    home.mkdir(exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GOOGLE_") and not k.startswith("GCLOUD")}
    env.update({"HOME": str(home), "GOOGLE_APPLICATION_CREDENTIALS": str(credentials), **item["env"]})
    server = Server(item["body"], item["status"], item["token_status"])
    with server as base:
        spec = {**filled(item["spec"], base, None), "tokenUrl": base + "/token"}
        lines = run(command, spec, env)
    item["check"](lines, server.requests)
    if compare and item["differential"]:
        reference_server = Server(item["body"], item["status"], item["token_status"])
        with reference_server as base:
            reference = oracle({**filled(item["spec"], base, None), "tokenUrl": base + "/token"}, env)
        item["check"](reference, reference_server.requests)
        native, upstream = trace(lines, server.requests), trace(reference, reference_server.requests)
        if native != upstream:
            import difflib
            diff = "\n".join(difflib.unified_diff(json.dumps(upstream, indent=1).splitlines(), json.dumps(native, indent=1).splitlines(), "upstream", "native", lineterm="", n=2))
            raise AssertionError(item["name"] + "\n" + diff[:6000])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    parser.add_argument("--only")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="google-vertex-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "google-vertex.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "google-vertex"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            for item in CASES:
                if args.only and args.only not in item["name"]:
                    continue
                run_case(command, item, directory, compare=True)
                print(f"PASS {backend}: {item['suite']}: {item['name']}")
        # providers/google-vertex.ts auth and the agent runtime's registration
        # (JavaScript lane).
        for source, label in ((AUTH, "google-vertex auth"), (REGISTERED, "agent runtime")):
            output = pathlib.Path(directory) / (source.stem + ".js")
            subprocess.run(["bun", args.toolchain, str(source), "-o", str(output)], cwd=ROOT, check=True)
            result = subprocess.run(["bun", str(output)], capture_output=True, text=True, timeout=300)
            assert result.returncode == 0, result
            for line in result.stdout.splitlines():
                print(f"{line.split(' ', 1)[0]} bun: {label}: {line.split(' ', 1)[1]}")


if __name__ == "__main__":
    main()
