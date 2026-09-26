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
import base64
import urllib.parse

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


def unb64(segment):
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


VERIFIED = {}


def token_body(body):
    """The JWT bearer grant with the assertion's times checked and elided and
    its RS256 signature verified with the service account's public key."""
    form = urllib.parse.parse_qs(body)
    if "assertion" not in form:
        return body
    header, payload, signature = form["assertion"][0].split(".")
    claims = json.loads(unb64(payload))
    assert claims["exp"] - claims["iat"] == 3600, claims
    message = (header + "." + payload).encode()
    with tempfile.NamedTemporaryFile() as data, tempfile.NamedTemporaryFile() as sig:
        data.write(message); data.flush(); sig.write(unb64(signature)); sig.flush()
        check = subprocess.run(["openssl", "dgst", "-sha256", "-verify", VERIFIED["public"], "-signature", sig.name, data.name], capture_output=True, text=True)
    assert check.returncode == 0, check
    return {"grant_type": form["grant_type"], "header": json.loads(unb64(header)), "claims": {**claims, "iat": "<now>", "exp": "<now+3600>"}, "headerText": unb64(header).decode(), "claimOrder": list(claims)}


def trace(lines, requests):
    return {
        "payload": payloads(lines),
        "events": [normalized(e) for e in lines["event"]],
        "result": [normalized(r) for r in lines["result"]],
        "thrown": lines["thrown"],
        "requests": [{"path": r["path"], "body": token_body(r["body"]) if r["path"] == "/token" else r["body"], "headers": {k: r["headers"].get(k) for k in COMPARED_HEADERS if not (k == "user-agent" and r["path"] == "/token")}} for r in requests],
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
def sa_request(lines, requests):
    m = message(lines)
    expect(m["stopReason"] == "toolUse", m)
    expect([r["path"] for r in requests][0] == "/token" and "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer" in requests[0]["body"], requests)
    expect(requests[1]["headers"].get("authorization") == "Bearer ya29.test-token" and requests[1]["headers"].get("x-goog-user-project") == "sa-quota", requests)


case("native", "a service account signs an RS256 JWT bearer assertion", adc_stream({"context": TOOLS, "serviceAccount": True}), sa_request, body=TEXT)
case("native", "a rejected service account assertion is gtoken's error message", adc_stream({"serviceAccount": True}), lambda lines, _: expect(message(lines)["errorMessage"] == "invalid_grant: Bad Request", lines), token_status=400)
case("native", "a stream without a finish reason names Google Vertex", {"model": {"baseUrl": "{base}"}, "context": HELLO, "options": {"apiKey": KEY}}, lambda lines, _: expect(message(lines)["errorMessage"] == "Google Vertex stream ended without a finish reason", lines), body=sse({"candidates": [{"content": {"parts": [{"text": "a"}], "role": "model"}}]}))


def filled(value, base, token):
    if isinstance(value, dict):
        return {k: filled(v, base, token) for k, v in value.items()}
    if isinstance(value, list):
        return [filled(v, base, token) for v in value]
    return base if value == "{base}" else value


def service_account(directory):
    key = pathlib.Path(directory) / "sa.pem"
    if not key.exists():
        subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(key)], check=True, capture_output=True)
        subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(key) + ".pub"], check=True, capture_output=True)
    VERIFIED["public"] = str(key) + ".pub"
    return {"type": "service_account", "project_id": "sa-project", "private_key_id": "key-id", "private_key": key.read_text(), "client_email": "vertex@sa-project.iam.gserviceaccount.com", "client_id": "1234", "token_uri": "https://oauth2.googleapis.com/token", "quota_project_id": "sa-quota"}


def run_case(command, item, directory, compare):
    credentials = pathlib.Path(directory) / "adc.json"
    credentials.write_text(json.dumps(service_account(directory) if item["spec"].get("serviceAccount") else ADC_FILE))
    home = pathlib.Path(directory) / "home"
    home.mkdir(exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GOOGLE_") and not k.startswith("GCLOUD")}
    env.update({"HOME": str(home), "GOOGLE_APPLICATION_CREDENTIALS": str(credentials), **item["env"]})
    server = Server(item["body"], item["status"], item["token_status"])
    with server as base:
        spec = {**filled(item["spec"], base, None), "googleBase": base}
        lines = run(command, spec, env)
    item["check"](lines, server.requests)
    if compare and item["differential"]:
        reference_server = Server(item["body"], item["status"], item["token_status"])
        with reference_server as base:
            reference = oracle({**filled(item["spec"], base, None), "googleBase": base}, env)
        item["check"](reference, reference_server.requests)
        native, upstream = trace(lines, server.requests), trace(reference, reference_server.requests)
        if native != upstream:
            import difflib
            diff = "\n".join(difflib.unified_diff(json.dumps(upstream, indent=1).splitlines(), json.dumps(native, indent=1).splitlines(), "upstream", "native", lineterm="", n=2))
            raise AssertionError(item["name"] + "\n" + diff[:6000])


# --- Application Default Credentials beyond authorized_user/service_account --
# No upstream suite covers them (upstream mocks the client); each case below
# resolves credentials from a credentials file, the environment and a
# loopback server standing in for Google's OAuth2, IAM Credentials and STS
# hosts, the subject-token and AWS metadata endpoints and the Compute Engine
# metadata server, then compares the requests those services saw, the Vertex
# request's authorization headers and the final message with upstream
# driving the pinned google-auth-library against its own copy of the setup.

import hashlib
import hmac
import shutil

FUTURE = "2099-01-01T00:00:00Z"
ACCOUNT = "target@project.iam.gserviceaccount.com"


def aws_checked(token):
    """The AWS subject token with its SigV4 signature verified and the
    date and signature elided."""
    request = json.loads(urllib.parse.unquote(token))
    headers = {h["key"]: h["value"] for h in request["headers"]}
    url = urllib.parse.urlsplit(request["url"])
    credential = re.search(r"Credential=([^/]+)/(\d+)/([^/]+)/([^/]+)/aws4_request, SignedHeaders=([^,]+), Signature=(\w+)", headers["authorization"])
    access, stamp, region, service, signed, signature = credential.groups()
    secret = {"AKIDAWS": "secret-aws", "AKIDENVAWS": "secret-env-aws"}[access]
    canonical = "\n".join([request["method"], url.path or "/", url.query] + [f"{name}:{headers[name]}" for name in signed.split(";")] + ["", signed, hashlib.sha256(b"").hexdigest()])
    scope = f"{stamp}/{region}/{service}/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", headers["x-amz-date"], scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = ("AWS4" + secret).encode()
    for part in (stamp, region, service, "aws4_request"):
        key = hmac.new(key, part.encode(), hashlib.sha256).digest()
    assert hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest() == signature, (request, canonical)
    return {"url": request["url"], "method": request["method"], "headerOrder": [h["key"] for h in request["headers"]],
            "headers": {k: ("<date>" if k == "x-amz-date" else re.sub(r"/\d{8}/", "/<stamp>/", re.sub(r"Signature=\w+", "Signature=<sig>", v))) for k, v in headers.items()}}


class AuthServer:
    """Google's auth hosts, subject-token sources, AWS and GCE metadata and
    the Vertex endpoint, on one port."""

    def __init__(self, behaviour=None):
        self.requests = []
        behaviour = behaviour or {}
        flaky = {"left": behaviour.get("flaky", 0)}
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def unavailable(self):
                """The first `flaky` auth requests answer 503."""
                if flaky["left"] > 0:
                    flaky["left"] -= 1
                    self.reply(503, json.dumps({"error": {"code": 503, "message": "Backend unavailable", "status": "UNAVAILABLE"}}))
                    return True
                return False

            def reply(self, status, body, kind="application/json", extra=None):
                data = body.encode()
                self.send_response(status)
                self.send_header("content-type", kind)
                for name, value in (extra or {}).items():
                    self.send_header(name, value)
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def pick(self, *names):
                headers = {k.lower(): v for k, v in self.headers.items()}
                picked = {name: re.sub(r"^gl-node/\S+ ?", "", headers[name]) if name == "x-goog-api-client" else headers[name] for name in names if name in headers}
                return {k: v for k, v in picked.items() if v != ""}

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                path = self.path
                if path.startswith("/v1/publishers/"):
                    outer.requests.append({"service": "vertex", "headers": self.pick("authorization", "x-goog-user-project")})
                    return self.reply(200, TEXT, "text/event-stream")
                if path == "/token":
                    form = urllib.parse.parse_qs(raw)
                    outer.requests.append({"service": "oauth2", "grant": form["grant_type"][0]})
                    if self.unavailable():
                        return
                    if behaviour.get("token_error"):
                        return self.reply(400, json.dumps({"error": "invalid_grant", "error_description": "Bad Request"}))
                    token = "ya29.sa" if "assertion" in form else "ya29.user"
                    return self.reply(200, json.dumps({"access_token": token, "expires_in": 3599, "token_type": "Bearer"}))
                if ":generateAccessToken" in path:
                    outer.requests.append({"service": "iamcredentials", "path": path, "headers": self.pick("authorization", "x-goog-user-project", "content-type"), "body": json.loads(raw)})
                    if behaviour.get("iam_error"):
                        return self.reply(403, json.dumps({"error": {"code": 403, "message": "Permission 'iam.serviceAccounts.getAccessToken' denied", "status": "PERMISSION_DENIED"}}))
                    return self.reply(200, json.dumps({"accessToken": "ya29.impersonated", "expireTime": FUTURE}))
                if path in ("/v1/token", "/v1/oauthtoken"):
                    form = {k: v[0] for k, v in urllib.parse.parse_qs(raw).items()}
                    if form.get("subject_token", "").startswith("%7B"):
                        form["subject_token"] = aws_checked(form["subject_token"])
                    outer.requests.append({"service": "sts" + path, "headers": self.pick("authorization", "content-type", "x-goog-api-client"), "form": form})
                    if self.unavailable():
                        return
                    if behaviour.get("sts_error"):
                        return self.reply(400, json.dumps({"error": "invalid_grant", "error_description": "The subject token is invalid"}))
                    token = "ya29.sts" if path == "/v1/token" else "ya29.external-user"
                    return self.reply(200, json.dumps({"access_token": token, "issued_token_type": "urn:ietf:params:oauth:token-type:access_token", "token_type": "Bearer", "expires_in": 3600}))
                return self.reply(404, "{}")

            def do_PUT(self):
                outer.requests.append({"service": "aws-metadata", "method": "PUT", "path": self.path, "headers": self.pick("x-aws-ec2-metadata-token-ttl-seconds")})
                return self.reply(200, "aws-session-token", "text/plain")

            def do_GET(self):
                path = self.path
                if path.startswith("/v1/projects/") and "cloudresourcemanager" not in path:
                    outer.requests.append({"service": "cloudresourcemanager", "path": path, "headers": self.pick("authorization", "x-goog-user-project")})
                    return self.reply(200, json.dumps({"projectNumber": "123456", "projectId": "resolved-project"}))
                if path.startswith("/computeMetadata/"):
                    outer.requests.append({"service": "gce-metadata", "path": path, "headers": self.pick("metadata-flavor")})
                    flavor = {} if behaviour.get("no_flavor") else {"Metadata-Flavor": "Google"}
                    if path == "/computeMetadata/v1/instance":
                        return self.reply(200, "", "text/plain", flavor)
                    if path == "/computeMetadata/v1/project/project-id":
                        return self.reply(200, "gce-project", "text/plain", flavor) if item_gce(behaviour) else self.reply(404, "Not Found", "text/plain", flavor)
                    if behaviour.get("gce_error"):
                        return self.reply(403, "Forbidden", "text/plain", flavor)
                    return self.reply(200, json.dumps({"access_token": "ya29.compute", "expires_in": 3599, "token_type": "Bearer"}), "application/json", flavor)
                if path.startswith("/subject"):
                    outer.requests.append({"service": "subject", "path": path, "headers": self.pick("x-subject")})
                    return self.reply(200, json.dumps({"id_token": "url-json-token"}) if path == "/subject-json" else "url-text-token", "application/json" if path == "/subject-json" else "text/plain")
                if path.startswith("/latest/"):
                    outer.requests.append({"service": "aws-metadata", "method": "GET", "path": path, "headers": self.pick("x-aws-ec2-metadata-token")})
                    if path == "/latest/meta-data/placement/availability-zone":
                        return self.reply(200, "us-east-1b", "text/plain")
                    if path == "/latest/meta-data/iam/security-credentials":
                        return self.reply(200, "aws-role", "text/plain")
                    if path == "/latest/meta-data/iam/security-credentials/aws-role":
                        return self.reply(200, json.dumps({"AccessKeyId": "AKIDAWS", "SecretAccessKey": "secret-aws", "Token": "token-aws"}))
                return self.reply(404, "{}")

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


USER = {"type": "authorized_user", "client_id": "client-id.apps.googleusercontent.com", "client_secret": "client-secret", "refresh_token": "refresh-token", "quota_project_id": "source-quota"}
IMPERSONATION = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" + ACCOUNT + ":generateAccessToken"
POOL = "//iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/pool/providers/provider"
WORKFORCE = "//iam.googleapis.com/locations/global/workforcePools/pool/providers/provider"
JWT_TYPE = "urn:ietf:params:oauth:token-type:jwt"


def external(source, **extra):
    return {"type": "external_account", "audience": POOL, "subject_token_type": JWT_TYPE, "token_url": "https://sts.googleapis.com/v1/token", "credential_source": source, **extra}


def item_gce(behaviour):
    return behaviour.get("gce", False)


# `diverges`: the native error message where upstream's differs through a
# JavaScript aliasing accident (see google-vertex-credentials.bend: a key
# file that does not construct a client falls back to a JWT key file; whether
# that JWT has scopes depends on fromJSON having mutated the shared options
# object, and without scopes upstream signs a self-signed JWT with no key).
class AdcCase:
    def __init__(self, name, credentials=None, well_known=None, env=None, behaviour=None, files=None, spawns=False, gce=False, diverges=None):
        self.name, self.credentials, self.well_known, self.env = name, credentials, well_known, env or {}
        self.behaviour, self.files, self.spawns, self.gce, self.diverges = dict(behaviour or {}, gce=gce), files or {}, spawns, gce, diverges


EXEC_SCRIPT = "#!/bin/sh\nprintf '{\"version\":1,\"success\":true,\"token_type\":\"urn:ietf:params:oauth:token-type:jwt\",\"id_token\":\"exec-%s-%s\",\"expiration_time\":4102444800}' \"$GOOGLE_EXTERNAL_ACCOUNT_INTERACTIVE\" \"$GOOGLE_EXTERNAL_ACCOUNT_TOKEN_TYPE\"\n"
ADC_CASES = [
    AdcCase("impersonates a service account with authorized_user source credentials", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "delegates": ["delegate@project.iam.gserviceaccount.com"], "quota_project_id": "impersonated-quota", "source_credentials": USER}),
    AdcCase("impersonates a service account with service_account source credentials", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "lifetime": 1200, "source_credentials": "{service_account}"}),
    AdcCase("reports a denied impersonation", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "source_credentials": USER}, behaviour={"iam_error": True}),
    AdcCase("reports a failed source token refresh for impersonation", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "source_credentials": USER}, behaviour={"token_error": True}),
    AdcCase("rejects impersonated credentials without a target principal", {"type": "impersonated_service_account", "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts", "source_credentials": USER}, diverges=("key must be a string, a buffer or an object", "private_key and client_email are required.")),
    AdcCase("rejects impersonated credentials without source credentials", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION}, diverges=("key must be a string, a buffer or an object", "private_key and client_email are required.")),
    AdcCase("exchanges a text subject token file at STS", external({"file": "{dir}/subject.txt"}), files={"subject.txt": "file-text-token"}),
    AdcCase("exchanges a JSON subject token file with client authentication", external({"file": "{dir}/subject.json", "format": {"type": "json", "subject_token_field_name": "id_token"}}, client_id="sts-client", client_secret="sts-secret", quota_project_id="external-quota"), files={"subject.json": json.dumps({"id_token": "file-json-token"})}),
    AdcCase("sends the workforce pool user project as an STS option", external({"file": "{dir}/subject.txt"}, audience=WORKFORCE, workforce_pool_user_project="workforce-project", subject_token_type="urn:ietf:params:oauth:token-type:id_token"), files={"subject.txt": "workforce-token"}),
    AdcCase("reads a URL subject token and impersonates a service account", external({"url": "{base}/subject-json", "headers": {"x-subject": "yes"}, "format": {"type": "json", "subject_token_field_name": "id_token"}}, service_account_impersonation_url="{base}/v1/projects/-/serviceAccounts/" + ACCOUNT + ":generateAccessToken", service_account_impersonation={"token_lifetime_seconds": 600})),
    AdcCase("reads a text URL subject token", external({"url": "{base}/subject-text"})),
    AdcCase("reports a missing subject token file", external({"file": "{dir}/missing.txt"})),
    AdcCase("reports a rejected token exchange", external({"file": "{dir}/subject.txt"}), files={"subject.txt": "file-text-token"}, behaviour={"sts_error": True}),
    AdcCase("rejects an invalid credential_source format", external({"file": "{dir}/subject.txt", "format": {"type": "xml"}}), diverges=("key must be a string, a buffer or an object", "private_key and client_email are required.")),
    AdcCase("signs an AWS GetCallerIdentity request with instance metadata credentials", external({"environment_id": "aws1", "region_url": "{base}/latest/meta-data/placement/availability-zone", "url": "{base}/latest/meta-data/iam/security-credentials", "imdsv2_session_token_url": "{base}/latest/api/token", "regional_cred_verification_url": "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"}, subject_token_type="urn:ietf:params:aws:token-type:aws4_request")),
    AdcCase("signs an AWS GetCallerIdentity request with environment credentials", external({"environment_id": "aws1", "region_url": "{base}/latest/meta-data/placement/availability-zone", "url": "{base}/latest/meta-data/iam/security-credentials", "regional_cred_verification_url": "{base}/{region}/verify?Action=GetCallerIdentity&Version=2011-06-15"}, subject_token_type="urn:ietf:params:aws:token-type:aws4_request"), env={"AWS_REGION": "eu-west-1", "AWS_ACCESS_KEY_ID": "AKIDENVAWS", "AWS_SECRET_ACCESS_KEY": "secret-env-aws"}),
    AdcCase("rejects an unsupported AWS environment version", external({"environment_id": "aws2", "regional_cred_verification_url": "https://sts.{region}.amazonaws.com"}), diverges=("key must be a string, a buffer or an object", "private_key and client_email are required.")),
    AdcCase("runs an allowed executable for the subject token", external({"executable": {"command": "{dir}/exec.sh --flag", "timeout_millis": 5000}}), files={"exec.sh": EXEC_SCRIPT}, env={"GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES": "1"}, spawns=True),
    AdcCase("refuses executables unless explicitly allowed", external({"executable": {"command": "{dir}/exec.sh"}}), files={"exec.sh": EXEC_SCRIPT}),
    AdcCase("refreshes external_account_authorized_user credentials", {"type": "external_account_authorized_user", "audience": WORKFORCE, "client_id": "ext-client", "client_secret": "ext-secret", "refresh_token": "ext-refresh", "token_url": "https://sts.googleapis.com/v1/oauthtoken", "quota_project_id": "ext-quota"}),
    AdcCase("reads unknown credential types as service accounts", {"type": "mystery"}),
    AdcCase("uses the Compute Engine metadata server without ADC files", gce=True),
    AdcCase("reports a forbidden Compute Engine token", gce=True, behaviour={"gce_error": True}),
    AdcCase("treats a metadata server without Metadata-Flavor as absent", gce=True, behaviour={"no_flavor": True}),
    AdcCase("retries a token refresh answered 503 under gaxios' policy", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "source_credentials": USER}, behaviour={"flaky": 2}),
    AdcCase("gives up on a token refresh after three retries", {"type": "impersonated_service_account", "service_account_impersonation_url": IMPERSONATION, "source_credentials": USER}, behaviour={"flaky": 5}),
    AdcCase("retries a token exchange answered 503", external({"file": "{dir}/subject.txt"}), files={"subject.txt": "file-text-token"}, behaviour={"flaky": 1}),
    AdcCase("reports no ADC when metadata detection is off"),
    AdcCase("rejects an unknown METADATA_SERVER_DETECTION value", env={"METADATA_SERVER_DETECTION": "sometimes"}),
    AdcCase("applies GOOGLE_CLOUD_QUOTA_PROJECT to well-known credentials", well_known=USER, env={"GOOGLE_CLOUD_QUOTA_PROJECT": "override-quota"}),
    AdcCase("skips project discovery when the environment names a project", well_known=USER, env={"GOOGLE_CLOUD_PROJECT": "env-project"}),
    AdcCase("looks up a well-known external account's project with its token", well_known=external({"file": "{dir}/subject.txt"}, quota_project_id="external-quota"), files={"subject.txt": "file-text-token"}),
]


def adc_fill(value, base, root, sa):
    if isinstance(value, dict):
        return {k: adc_fill(v, base, root, sa) for k, v in value.items()}
    if isinstance(value, list):
        return [adc_fill(v, base, root, sa) for v in value]
    if value == "{service_account}":
        return sa
    if isinstance(value, str):
        return value.replace("{base}", base).replace("{dir}", str(root))
    return value


def adc_run(command, item, directory):
    server = AuthServer(item.behaviour)
    root = pathlib.Path(directory)
    if root.exists():
        shutil.rmtree(root)
    (root / "home").mkdir(parents=True)
    sa = service_account(str(root.parent))
    for name, text in item.files.items():
        (root / name).write_text(text)
        if name.endswith(".sh"):
            (root / name).chmod(0o755)
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GOOGLE_", "GCLOUD", "AWS_", "GCE_", "METADATA_"))}
    env.update({"HOME": str(root / "home")})
    env["GCE_METADATA_HOST"] = server.url.removeprefix("http://")
    if not item.gce:
        env["METADATA_SERVER_DETECTION"] = "none"
    if item.credentials is not None:
        (root / "adc.json").write_text(json.dumps(adc_fill(item.credentials, server.url, root, sa)))
        env["GOOGLE_APPLICATION_CREDENTIALS"] = str(root / "adc.json")
    if item.well_known is not None:
        (root / "home/.config/gcloud").mkdir(parents=True)
        (root / "home/.config/gcloud/application_default_credentials.json").write_text(json.dumps(adc_fill(item.well_known, server.url, root, sa)))
    env.update({k: adc_fill(v, server.url, root, sa) for k, v in item.env.items()})
    spec = {**adc_stream(), "model": {"baseUrl": server.url}, "googleBase": server.url}
    try:
        lines = run(command, spec, env) if command else oracle(spec, env)
    finally:
        server.close()
    result = message(lines)
    requests = json.loads(json.dumps(server.requests).replace(server.url, "{base}").replace(server.url.removeprefix("http://"), "{host}").replace(str(root), "{dir}"))
    return {"requests": requests, "stopReason": result["stopReason"], "errorMessage": result.get("errorMessage", "").replace(server.url, "{base}").replace(str(root), "{dir}")}


def adc_check(command, item, directory):
    native = adc_run(command, item, pathlib.Path(directory) / "adc-native")
    upstream = adc_run(None, item, pathlib.Path(directory) / "adc-oracle")
    if item.diverges:
        expect(upstream["errorMessage"] == item.diverges[0] and native["errorMessage"] == item.diverges[1], (upstream, native))
        native, upstream = dict(native, errorMessage=None), dict(upstream, errorMessage=None)
    if native != upstream:
        import difflib
        raise AssertionError(item.name + "\n" + "\n".join(difflib.unified_diff(json.dumps(upstream, indent=1).splitlines(), json.dumps(native, indent=1).splitlines(), "upstream", "native", lineterm="", n=2)))


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
            for item in ADC_CASES:
                if args.only and args.only not in item.name:
                    continue
                if item.spawns and backend == "bun":
                    # The JavaScript lane has no process spawning; native runs it.
                    continue
                adc_check(command, item, directory)
                print(f"PASS {backend}: application default credentials: {item.name}")
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
