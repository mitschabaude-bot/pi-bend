#!/usr/bin/env python3
"""Exercise Google Generative AI over the native Fetch/SSE path."""
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / "pi-mono"


def oracle(mode):
    result = subprocess.run(
        ["bun", str(ROOT / "packages/ai/test/google-request-oracle.ts"), mode],
        cwd=ROOT,
        env=dict(os.environ, PI_MONO_ROOT=str(UPSTREAM)),
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def event_oracle(payload, simple=False):
    result = subprocess.run(
        ["bun", str(ROOT / "packages/ai/test/google-stream-oracle.ts"), "simple" if simple else "raw"],
        cwd=ROOT,
        env=dict(os.environ, PI_MONO_ROOT=str(UPSTREAM), GOOGLE_SSE=payload.decode()),
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


class Handler(http.server.BaseHTTPRequestHandler):
    bodies = []
    request_headers = []
    response = b""
    status = 200
    statuses = []
    tool_mode = False
    tool_start = b""
    tool_finish = b""

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["content-length"])))
        self.bodies.append((self.path, self.headers.get("x-goog-api-key"), body))
        self.request_headers.append(self.headers)
        response = self.response
        if self.tool_mode:
            is_result = any(
                "functionResponse" in part
                for item in body["contents"]
                for part in item["parts"]
            )
            response = self.tool_finish if is_result else self.tool_start
        self.send_response(self.statuses.pop(0) if self.statuses else self.status)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *_):
        pass


def invoke(command, base, output, code=0, mode=None):
    result = subprocess.run([*command, base, *([mode] if mode else [])], capture_output=True, text=True, timeout=30)
    if result.returncode != code or result.stdout.strip() != output:
        raise AssertionError((command, result.returncode, result.stdout, result.stderr))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", default="/tmp/pi-bend-theme-controller/build/theme-toolchain/bend2/main.ts")
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=UPSTREAM, text=True).strip()
    if not revision.startswith("f07218c4d"):
        raise RuntimeError(f"Expected pinned pi-mono f07218c4d, found {revision}")
    sources = {
        "client": ROOT / "packages/ai/test/google-generative-ai-client.bend",
        "provider": ROOT / "packages/coding-agent/test/google-provider-loopback.bend",
        "signed": ROOT / "packages/ai/test/google-request-value.bend",
        "catalog": ROOT / "packages/ai/test/google-catalog.bend",
    }
    with tempfile.TemporaryDirectory(prefix="google-loopback-") as directory:
        commands = []
        for kind, source in sources.items():
            if args.backend in ("bun", "all"):
                output = pathlib.Path(directory) / f"{kind}.js"
                subprocess.run(["bun", args.toolchain, str(source), "-o", str(output)], cwd=ROOT, check=True)
                commands.append((kind, "bun", ["bun", str(output)]))
            if args.backend in ("native", "all"):
                output = pathlib.Path(directory) / kind
                subprocess.run(["sh", "scripts/build-pure.sh", str(source.relative_to(ROOT)), str(output)], cwd=ROOT, env=dict(os.environ, BEND=args.toolchain), check=True)
                commands.extend([(kind, "native1", [str(output), "--threads", "1"]), (kind, "native4", [str(output), "--threads", "4"])])

        for kind, name, command in commands:
            if kind == "signed":
                for mode in ("signed", "strict", "strict-prefer", "legacy-image", "modern-image", "system-update"):
                    result = subprocess.run([*command, mode], capture_output=True, text=True, timeout=30, check=True)
                    assert json.loads(result.stdout) == oracle(mode), (mode, result.stdout)
                result = subprocess.run([*command, "strict-unsupported"], capture_output=True, text=True, timeout=30, check=True)
                assert result.stdout.strip() == "error: " + oracle("strict-unsupported")["error"]
                print(f"{kind} {name}: signed replay, strict schema, unsupported mode, and image result routing match upstream")
            if kind == "catalog":
                result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
                expected = list(json.loads((UPSTREAM / "packages/ai/src/providers/data/google.json").read_text())["google-generative-ai"].values())
                assert json.loads(result.stdout) == expected, "Google model catalog differs from pinned source data"
                print(f"{kind} {name}: all {len(expected)} models match upstream metadata")

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}/v1beta"
        try:
            Handler.response = b'data: {"responseId":"r1","candidates":[{"content":{"parts":[{"text":"Hi"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}\n\n'
            for kind, name, command in commands:
                if kind in ("signed", "catalog"):
                    continue
                expected = event_oracle(Handler.response, simple=kind == "provider")
                invoke(command, base, expected + ("\nsuccess" if kind == "client" else ""))
                print(f"{kind} {name}: live SSE text passes")
            for index, (path, key, body) in enumerate(Handler.bodies):
                assert path == "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse", path
                assert key == "test-google-key", key
                assert body["contents"] == [{"role": "user", "parts": [{"text": "ping"}]}], body
                expected = oracle("basic" if commands[index][0] == "client" else "simple-basic")
                assert body == expected, (body, expected)
                if commands[index][0] == "provider":
                    node_agent = subprocess.check_output(["node", "-e", "const os=require('node:os');process.stdout.write(`pi (${os.platform()} ${os.release()}; ${os.arch()})`)"], text=True)
                    assert Handler.request_headers[index].get("User-Agent") == node_agent, Handler.request_headers[index]
                    print(f"provider {commands[index][1]}: default User-Agent matches Node OS identity")
            Handler.bodies.clear()
            Handler.request_headers.clear()
            Handler.response = b'data: {"responseId":"thought-1","candidates":[{"content":{"parts":[{"text":"Why","thought":true,"thoughtSignature":"c2ln"},{"text":"Hello"}]},"finishReason":"STOP"}]}\n\n'
            for kind, name, command in commands:
                if kind in ("signed", "catalog"):
                    continue
                expected = event_oracle(Handler.response, simple=kind == "provider")
                invoke(command, base, expected + ("\nsuccess" if kind == "client" else ""))
                print(f"{kind} {name}: thinking/text transition matches upstream")

            Handler.response = b'data: {"candidates":[{"finishReason":"SAFETY"}]}\n\n'
            for kind, name, command in commands:
                if kind in ("signed", "catalog"):
                    continue
                invoke(command, base, event_oracle(Handler.response, simple=kind == "provider"), 1 if kind == "client" else 0)
                print(f"{kind} {name}: terminal finish error passes")

            Handler.status = 429
            Handler.response = b'{"error":{"message":"rate limited"}}'
            for kind, name, command in commands:
                if kind in ("signed", "catalog"):
                    continue
                invoke(command, base, "error", 1 if kind == "client" else 0)
                print(f"{kind} {name}: HTTP failure surfaces terminal error")
            Handler.status = 200

            Handler.response = b'data: {"responseId":"retry-ok","candidates":[{"content":{"parts":[{"text":"recovered"}]},"finishReason":"STOP"}]}\n\n'
            for kind, name, command in commands:
                if kind == "provider":
                    Handler.statuses = [429, 200]
                    start = len(Handler.bodies)
                    invoke(command, base, event_oracle(Handler.response, simple=True), mode="retry")
                    assert len(Handler.bodies) - start == 2, Handler.bodies[start:]
                    assert Handler.bodies[start][2] == Handler.bodies[start + 1][2]
                    print(f"{kind} {name}: 429 retries once before SSE events")

                    Handler.statuses = [400]
                    start = len(Handler.bodies)
                    invoke(command, base, "error", mode="retry")
                    assert len(Handler.bodies) - start == 1
                    print(f"{kind} {name}: 400 is not retried")

                    start = len(Handler.bodies)
                    invoke(command, base, event_oracle(Handler.response, simple=True), mode="hook")
                    assert len(Handler.bodies) - start == 1
                    assert Handler.bodies[start][2] == oracle("hook"), (Handler.bodies[start][2], oracle("hook"))
                    print(f"{kind} {name}: onPayload replacement changes the live request")

                    start = len(Handler.bodies)
                    invoke(command, base, event_oracle(Handler.response, simple=True), mode="headers")
                    assert len(Handler.bodies) - start == 1
                    headers = Handler.request_headers[start]
                    assert headers.get("User-Agent") == "custom-agent", headers
                    assert headers.get("X-Google-Test") == "option", headers
                    print(f"{kind} {name}: caller headers override request defaults")

            Handler.tool_start = b'data: {"responseId":"tool-1","candidates":[{"content":{"parts":[{"functionCall":{"id":"call-1","name":"lookup","args":{"value":"42"}}}]},"finishReason":"STOP"}]}\n\n'
            Handler.tool_finish = b'data: {"responseId":"tool-2","candidates":[{"content":{"parts":[{"text":"found"}]},"finishReason":"STOP"}]}\n\n'
            Handler.tool_mode = True
            for kind, name, command in commands:
                if kind == "provider":
                    start = len(Handler.bodies)
                    expected = event_oracle(Handler.tool_start, simple=True) + "\n" + event_oracle(Handler.tool_finish, simple=True)
                    invoke(command, base, expected, mode="tool")
                    requests = Handler.bodies[start:]
                    assert len(requests) == 2, requests
                    first, second = requests[0][2], requests[1][2]
                    assert first["systemInstruction"]["parts"] == [{"text": "Use the lookup tool."}], first
                    assert first["tools"][0]["functionDeclarations"][0]["name"] == "lookup", first
                    model_turn = next(item for item in second["contents"] if item["role"] == "model")
                    result_turn = next(item for item in second["contents"] if any("functionResponse" in part for part in item["parts"]))
                    assert model_turn["parts"][0]["functionCall"]["args"] == {"value": "42"}, model_turn
                    assert result_turn["parts"][0]["functionResponse"]["response"] == {"output": "found 42"}, result_turn
                    assert first == oracle("tool-first"), (first, oracle("tool-first"))
                    assert second == oracle("tool-replay"), (second, oracle("tool-replay"))
                    print(f"{kind} {name}: two-turn tool replay passes")
        finally:
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    main()
