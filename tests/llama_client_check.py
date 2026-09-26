#!/usr/bin/env python3
"""Llama management client over a local router; no external service required.

Compile tests/llama-client.bend to build/llama-client(.js), then run this check.
Requests are checked against the pinned TS client using the same fixture.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
MODEL = {
    "id": "qwen", "aliases": ["alias"],
    "status": {"value": "loaded", "args": ["server"], "failed": False},
    "architecture": {"input_modalities": ["text", "image"]},
    "source": "preset", "meta": {"n_ctx": 32768, "n_ctx_train": 65536, "ftype": "Q4"},
}


class Router(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record_request(self):
        data = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.server.requests.append({"method": self.command, "path": self.path,
            "authorization": self.headers.get("Authorization"),
            "content_type": self.headers.get("Content-Type"),
            "body": json.loads(data) if data else None})
        return data

    def do_GET(self):
        self.record_request()
        path = urllib.parse.urlsplit(self.path)
        if path.path == "/failure/models":
            self.respond({"error": {"message": "router unavailable"}}, 503)
        elif path.path == "/props":
            assert urllib.parse.parse_qs(path.query) == {"model": ["qwen + coder"], "autoload": ["false"]}
            self.respond({"models_autoload": True, "chat_template": "enable_thinking"})
        elif path.path == "/models":
            model = dict(MODEL)
            if self.server.unload_polls is not None:
                self.server.unload_polls += 1
                model["status"] = {"value": "loading" if self.server.unload_polls == 1 else "unloaded"}
            self.respond({"data": [model]})
        else:
            self.respond({}, 404)

    def do_POST(self):
        self.record_request()
        if self.path == "/models/unload":
            self.server.unload_polls = 0
        self.respond({})


def run(argv, env=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Router)
    server.requests = []
    server.unload_polls = None
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}"
        result = subprocess.run([*argv, base], cwd=ROOT, env=env, capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, (argv, result.stdout, result.stderr)
        assert not result.stderr, result.stderr
        return result.stdout, server.requests
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    # Running the pinned source through Bun is a test oracle only.
    _, reference = run(["bun", "tests/llama_client_reference.ts"])
    lanes = []
    if args.backend in ("bun", "all"):
        lanes.append(("bun", ["bun", "build/llama-client.js"], os.environ.copy()))
    if args.backend in ("native", "all"):
        lanes.extend((f"native{n}", [str(ROOT / "build/llama-client")], {**os.environ, "BEND_THREADS": str(n)}) for n in (1, 4))
    for lane, argv, env in lanes:
        output, requests = run(argv, env)
        assert "llama management requests passed" in output, output
        assert requests == reference, (lane, requests, reference)
        print(f"{lane}: typed catalog/props, normalization, authenticated commands, unload polling, server errors, cancellation MATCH")


if __name__ == "__main__":
    main()
