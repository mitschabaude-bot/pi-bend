#!/usr/bin/env python3
"""upstream packages/ai/test/pi-messages.test.ts over the native pi-messages API.

Each named case starts the upstream test's loopback server (same responses,
chunked SSE), runs packages/ai/test/pi-messages.bend on the selected
backends, asserts the upstream expectations, and compares the whole event
trace with upstream pi-messages.ts serving the same responses
(packages/ai/test/pi-messages-oracle.ts). Timestamps are the only values
normalized; event fields outside the typed AssistantMessageEvent union
(wire-only members upstream spreads into events) are dropped from the
upstream side.
"""
from upstream_pin import UPSTREAM
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/ai/test/pi-messages.bend"
ORACLE = ROOT / "packages/ai/test/pi-messages-oracle.ts"
REGISTERED = ROOT / "packages/coding-agent/test/registered-apis.bend"

USAGE = {
    "input": 10,
    "output": 5,
    "cacheRead": 0,
    "cacheWrite": 0,
    "totalTokens": 15,
    "cost": {"input": 0.1, "output": 0.2, "cacheRead": 0, "cacheWrite": 0, "total": 0.3},
}


class Server:
    def __init__(self, status=200, headers=None, events=None, raw_body=None, chunks=None):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("content-length", "0"))).decode()
                outer.requests.append({"url": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(raw) if raw else None})
                if status != 200:
                    body = (raw_body or "{}").encode()
                    self.send_response(status)
                    self.send_header("content-type", "application/json")
                    self.send_header("content-length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                self.send_header("transfer-encoding", "chunked")
                self.end_headers()
                pieces = chunks if chunks is not None else [f"data: {json.dumps(event)}\n\n" for event in events or []]
                for piece in pieces:
                    chunk = piece.encode()
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}/v1"

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()


def parse(output):
    lines = {"event": [], "observed": [], "result": []}
    for line in output.splitlines():
        kind, _, rest = line.partition(" ")
        lines[kind].append(rest if kind == "observed" else json.loads(rest))
    return lines


def run(command, mode, base):
    result = subprocess.run([*command, mode, base], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise AssertionError((command, mode, result.returncode, result.stdout, result.stderr))
    return parse(result.stdout)


# Members of each event type in the typed AssistantMessageEvent union.
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
        return {k: ("<time>" if k in ("timestamp", "timestampMs") else normalized(v)) for k, v in value.items() if k in keys}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    return value


def trace(lines):
    return {"events": [normalized(e, True) for e in lines["event"]], "result": [normalized(r) for r in lines["result"]], "observed": lines["observed"]}


def oracle(mode, base):
    result = subprocess.run(["bun", str(ORACLE), mode, base], capture_output=True, text=True, timeout=60, env=dict(os.environ, PI_MONO=str(UPSTREAM)))
    if result.returncode != 0:
        raise AssertionError(("oracle", mode, result.stdout, result.stderr))
    return parse(result.stdout)


def compare(mode, lines, reference, name):
    native, upstream = trace(lines), trace(reference)
    assert native == upstream, (name, mode, json.dumps(native, indent=1), json.dumps(upstream, indent=1))


def case_stream(command):
    events = [
        {"type": "start"},
        {"type": "text_start", "contentIndex": 0},
        {"type": "text_delta", "contentIndex": 0, "delta": "Hel"},
        {"type": "text_delta", "contentIndex": 0, "delta": "lo"},
        {"type": "text_end", "contentIndex": 0, "content": "Hello"},
        {"type": "toolcall_start", "contentIndex": 1, "id": "call_1", "toolName": "read"},
        {"type": "toolcall_delta", "contentIndex": 1, "delta": '{"path":'},
        {"type": "toolcall_delta", "contentIndex": 1, "delta": '"a.txt"}'},
        {"type": "toolcall_end", "contentIndex": 1, "toolCall": {"type": "toolCall", "id": "call_1", "name": "read", "arguments": {"path": "a.txt"}}},
        {"type": "done", "reason": "toolUse", "usage": USAGE, "responseId": "resp_1", "providerThinkingLevel": "high"},
    ]
    server = Server(events=events)
    with server as base:
        lines = run(command, "stream", base)
        reference = oracle("stream", base)
    partial_stop = [e["partial"]["stopReason"] for e in lines["event"] if "partial" in e]
    message = lines["result"][0]
    assert partial_stop[0] == "pending"
    assert message["stopReason"] == "toolUse"
    assert message["usage"] == USAGE
    assert message["responseId"] == "resp_1"
    assert message["providerThinkingLevel"] == "high"
    assert message["model"] == "auto" and message["provider"] == "radius"
    assert message["content"] == [
        {"type": "text", "text": "Hello"},
        {"type": "toolCall", "id": "call_1", "name": "read", "arguments": {"path": "a.txt"}},
    ], message["content"]
    assert any(e["type"] == "text_delta" for e in lines["event"])
    assert len([e for e in lines["event"] if e["type"] == "toolcall_end"]) == 1
    assert len(server.requests) == 2  # the native run and the upstream run
    request = server.requests[0]
    assert request["url"] == "/v1/messages"
    assert request["headers"]["authorization"] == "Bearer test-key"
    assert request["headers"]["x-custom"] == "1"
    assert request["body"] == {
        "model": "auto",
        "context": {"messages": [{"role": "user", "content": "Hello", "timestamp": 1700000000}]},
        "options": {"maxTokens": 100, "sessionId": "session-1", "toolChoice": "auto"},
    }, request["body"]
    assert server.requests[0] == server.requests[1] | {"headers": server.requests[0]["headers"]}
    return lines, reference


def case_debug(command):
    server = Server(headers={"x-pi-gateway-upstream-provider": "anthropic"}, events=[{"type": "done", "reason": "stop", "usage": USAGE}])
    with server as base:
        lines = run(command, "debug", base)
        reference = oracle("debug", base)
    assert lines["result"][0]["stopReason"] == "stop"
    assert server.requests[0]["url"] == "/v1/messages?debug=1"
    assert lines["observed"] == ["anthropic"]
    return lines, reference


def case_error_response(command):
    server = Server(status=401, raw_body=json.dumps({"error": {"message": "Token expired", "code": "unauthorized"}}))
    with server as base:
        lines = run(command, "stale", base)
        reference = oracle("stale", base)
    message = lines["result"][0]
    assert message["stopReason"] == "error"
    assert "401" in message["errorMessage"]
    assert "Token expired" in message["errorMessage"]
    assert "unauthorized" in message["errorMessage"]
    assert message["diagnostics"][0]["type"] == "pi_messages_response_failure"
    assert message["diagnostics"][0]["details"]["status"] == 401
    # The native diagnostic has no JavaScript stack.
    for value in (lines, reference):
        for diagnostic in value["result"][0]["diagnostics"]:
            diagnostic["error"].pop("stack", None)
        for event in value["event"]:
            for diagnostic in event["error"].get("diagnostics", []):
                diagnostic["error"].pop("stack", None)
    for value in (lines, reference):
        for diagnostic in value["result"][0]["diagnostics"]:
            diagnostic["details"]["url"] = diagnostic["details"]["url"].rsplit(":", 1)[0]
    return lines, reference


def case_server_error(command):
    server = Server(events=[{"type": "start"}, {"type": "error", "reason": "error", "usage": USAGE, "errorMessage": "Upstream failed"}])
    with server as base:
        lines = run(command, "server-error", base)
        reference = oracle("server-error", base)
    message = lines["result"][0]
    assert message["stopReason"] == "error"
    assert message["errorMessage"] == "Upstream failed"
    assert message["usage"] == USAGE
    return lines, reference


def case_no_key(command):
    base = "http://127.0.0.1:1/v1"
    lines = run(command, "no-key", base)
    reference = oracle("no-key", base)
    message = lines["result"][0]
    assert message["stopReason"] == "error"
    assert "No API key provided" in message["errorMessage"]
    return lines, reference


def case_unterminated(command):
    server = Server(events=[{"type": "start"}, {"type": "text_start", "contentIndex": 0}, {"type": "text_delta", "contentIndex": 0, "delta": "partial"}])
    with server as base:
        lines = run(command, "unterminated", base)
        reference = oracle("unterminated", base)
    message = lines["result"][0]
    assert message["stopReason"] == "error"
    assert "stream ended without a terminal event" in message["errorMessage"]
    return lines, reference


# Supplemental: CRLF framing split across chunks, comment and event lines,
# a [DONE] marker, thinking signatures and redaction, a rewrite diagnostic,
# and a final event without a trailing blank line.
def case_framing(command):
    rewrite = {"policyId": "p1", "policyVersion": 3, "changed": True, "tokenCountChange": -12, "messageCountChange": -1, "systemPromptChanged": False}
    chunks = [
        'data: {"type":"start"}\r\n\r\n',
        'data: {"type":"thinking_start","contentIndex":0}\r',
        '\n\r\ndata: {"type":"thinking_delta","contentIndex":0,"delta":"why \u00e9"}\n\n',
        ': comment\nevent: note\ndata: {"type":"thinking_end","contentIndex":0,"content":"why \u00e9!","contentSignature":"sig","redacted":true}\n\n',
        'data: [DONE]\n\n',
        'data:   {"type":"text_start","contentIndex":1}  \n\n',
        'data: {"type":"text_end","contentIndex":1,"content":"answer","contentSignature":"t1"}\n\n',
        'data: ' + json.dumps({"type": "done", "reason": "stop", "usage": USAGE, "rewrite": rewrite}),
    ]
    server = Server(chunks=chunks)
    with server as base:
        lines = run(command, "framing", base)
        reference = oracle("framing", base)
    message = lines["result"][0]
    assert message["content"] == [
        {"type": "thinking", "thinking": "why \u00e9!", "thinkingSignature": "sig", "redacted": True},
        {"type": "text", "text": "answer", "textSignature": "t1"},
    ], message["content"]
    assert message["diagnostics"][0]["type"] == "pi_messages_rewrite"
    assert message["diagnostics"][0]["details"] == rewrite
    return lines, reference


CASES = [
    ("streams text and tool calls and resolves the terminal message", "stream", case_stream),
    ("appends debug=1 and reports response headers via onResponse", "debug", case_debug),
    ("surfaces backend error responses with diagnostics", "stale", case_error_response),
    ("propagates server-sent error events", "server-error", case_server_error),
    ("errors when no API key is provided", "no-key", case_no_key),
    ("errors when the stream ends without a terminal event", "unterminated", case_unterminated),
    ("supplemental: framing, thinking signatures and rewrite diagnostics", "framing", case_framing),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default=str(ROOT / "build/bend-native-toolchain/bend2/main.ts"))
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pi-messages-") as directory:
        commands = []
        if args.backend in ("bun", "all"):
            output = pathlib.Path(directory) / "pi-messages.js"
            subprocess.run(["bun", args.toolchain, str(SOURCE), "-o", str(output)], cwd=ROOT, check=True)
            commands.append(("bun", ["bun", str(output)]))
        if args.backend in ("native", "all"):
            output = pathlib.Path(directory) / "pi-messages"
            subprocess.run(["flock", "/tmp/pi-bend-build.lock", "sh", "scripts/build-pure.sh", str(SOURCE.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
            commands.extend([("native1", [str(output), "--threads", "1"]), ("native4", [str(output), "--threads", "4"])])
        for backend, command in commands:
            for name, mode, case in CASES:
                lines, reference = case(command)
                compare(mode, lines, reference, name)
                print(f"PASS {backend}: {name} (matches upstream trace)")
            api = subprocess.run([*command, "api", "-"], capture_output=True, text=True, timeout=60)
            assert api.returncode == 0 and api.stdout.split() == ["api", "pi-messages", "registered"], api
            print(f"PASS {backend}: is a known api usable on models")
        # upstream "is registered as a builtin api provider": the agent
        # runtime's dispatch (JavaScript lane; it compiles the whole runtime).
        output = pathlib.Path(directory) / "registered-apis.js"
        subprocess.run(["bun", args.toolchain, str(REGISTERED), "-o", str(output)], cwd=ROOT, check=True)
        registered = subprocess.run(["bun", str(output)], capture_output=True, text=True, timeout=120)
        assert registered.returncode == 0 and "PASS pi-messages is registered as a builtin api provider" in registered.stdout, registered
        print("PASS bun: is registered as a builtin api provider")


if __name__ == "__main__":
    main()
