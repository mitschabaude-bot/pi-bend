#!/usr/bin/env python3
"""Exercise native Anthropic HTTP/SSE success and failure on a local server."""
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
EVENTS = "start\ntext_start\ntext_delta\ntext_end\ndone"


def event(name, payload):
    return f"event: {name}\ndata: {json.dumps(payload, separators=(',', ':'))}\n\n"


class Handler(http.server.BaseHTTPRequestHandler):
    requests = []
    response = b""
    tool_mode = False
    tool_start = b""
    tool_finish = b""
    oauth_requests = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers["content-length"]))
        decoded = json.loads(body)
        if self.path == "/v1/oauth/token":
            self.oauth_requests.append(decoded)
            response = b'{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}'
            self.send_response(200)
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)
            return
        self.requests.append((self.path, self.headers.get("x-api-key"), self.headers.get("anthropic-beta"), decoded))
        response = self.response
        if self.tool_mode:
            is_result = any(
                block.get("type") == "tool_result"
                for item in decoded["messages"]
                if isinstance(item["content"], list)
                for block in item["content"]
            )
            response = self.tool_finish if is_result else self.tool_start
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *_):
        pass


def invoke(command, address, expected_code, expected_output):
    result = subprocess.run([*command, address], text=True, capture_output=True, timeout=30)
    if result.returncode != expected_code or result.stdout.strip() != expected_output:
        raise AssertionError((command, result.returncode, result.stdout, result.stderr))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default="/tmp/pi-bend-theme-controller/build/theme-toolchain/bend2/main.ts")
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    sources = {
        "client": ROOT / "packages/ai/test/anthropic-messages-client.bend",
        "provider": ROOT / "packages/coding-agent/test/anthropic-provider-loopback.bend",
        "oauth": ROOT / "packages/ai/test/anthropic-oauth-refresh.bend",
    }
    with tempfile.TemporaryDirectory(prefix="anthropic-loopback-") as directory:
        target = pathlib.Path(directory)
        commands = []
        for kind, source in sources.items():
            if args.backend in ("bun", "all"):
                output = target / f"{kind}.js"
                subprocess.run(["bun", args.toolchain, str(source), "-o", str(output)], cwd=ROOT, check=True)
                commands.append((kind, "bun", ["bun", str(output)]))
            if args.backend in ("native", "all"):
                output = target / kind
                environment = dict(os.environ, BEND=args.toolchain)
                subprocess.run(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", str(source.relative_to(ROOT)), str(output)], cwd=ROOT, env=environment, check=True)
                commands += [(kind, "native1", [str(output), "--threads", "1"]), (kind, "native4", [str(output), "--threads", "4"])]

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        address = f"http://127.0.0.1:{server.server_port}"
        try:
            Handler.response = "".join([
                event("message_start", {"type": "message_start", "message": {"id": "m1", "model": "claude-opus-5", "usage": {"input_tokens": 2, "output_tokens": 0}}}),
                event("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
                event("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hi"}}),
                event("content_block_stop", {"type": "content_block_stop", "index": 0}),
                event("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 1}}),
                event("message_stop", {"type": "message_stop"}),
            ]).encode()
            for kind, name, command in commands:
                if kind != "oauth":
                    invoke(command, address, 0, EVENTS + ("\nsuccess" if kind == "client" else ""))
                    print(f"{kind} {name}: live request and SSE events pass")
            Handler.response = event("error", {"type": "error", "error": {"message": "nope"}}).encode()
            for kind, name, command in commands:
                if kind != "oauth":
                    invoke(command, address, 1 if kind == "client" else 0, "start\nerror")
                    print(f"{kind} {name}: terminal SSE error passes")
            Handler.tool_start = "".join([
                event("message_start", {"type": "message_start", "message": {"id": "mtool", "model": "claude-opus-5", "usage": {"input_tokens": 3, "output_tokens": 0}}}),
                event("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "toolu_1", "name": "lookup", "input": {}}}),
                event("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta", "partial_json": '{"value":"42"}'}}),
                event("content_block_stop", {"type": "content_block_stop", "index": 0}),
                event("message_delta", {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 2}}),
                event("message_stop", {"type": "message_stop"}),
            ]).encode()
            Handler.tool_finish = "".join([
                event("message_start", {"type": "message_start", "message": {"id": "mfinish", "model": "claude-opus-5", "usage": {"input_tokens": 5, "output_tokens": 0}}}),
                event("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": "found"}}),
                event("content_block_stop", {"type": "content_block_stop", "index": 0}),
                event("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 1}}),
                event("message_stop", {"type": "message_stop"}),
            ]).encode()
            Handler.tool_mode = True
            for kind, name, command in commands:
                if kind == "provider":
                    start = len(Handler.requests)
                    invoke([*command, address], "tool", 0, "start\ntoolcall_start\ntoolcall_delta\ntoolcall_end\ndone\nstart\ntext_start\ntext_end\ndone")
                    requests = Handler.requests[start:]
                    if len(requests) != 2:
                        raise AssertionError(requests)
                    second = requests[1][3]["messages"]
                    assistant = next(item for item in second if item["role"] == "assistant")
                    result = next(block for item in second if item["role"] == "user" and isinstance(item["content"], list) for block in item["content"] if block["type"] == "tool_result")
                    if assistant["content"][0]["input"] != {"value": "42"} or result["tool_use_id"] != "toolu_1" or result["content"] != "found 42":
                        raise AssertionError((assistant, result))
                    print(f"{kind} {name}: tool call and result replay pass")
            Handler.tool_mode = False
            for kind, name, command in commands:
                if kind == "oauth":
                    invoke(command, address + "/v1/oauth/token", 0, "OAuth refresh pass")
                    print(f"{kind} {name}: native refresh and credential derivation pass")
            if len(Handler.oauth_requests) != sum(kind == "oauth" for kind, _, _ in commands):
                raise AssertionError("missing OAuth refresh request")
            for body in Handler.oauth_requests:
                if body != {"grant_type": "refresh_token", "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e", "refresh_token": "old-refresh"}:
                    raise AssertionError("unexpected OAuth refresh payload")
            for path, key, beta, body in Handler.requests:
                if path != "/v1/messages?beta=true" or key != "test-key" or body["model"] != "claude-opus-5" or body["stream"] is not True or "betas" in body or "mid-conversation-output-config-2026-07-01" not in (beta or ""):
                    raise AssertionError((path, key, beta, body))
        finally:
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    main()
