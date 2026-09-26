#!/usr/bin/env python3
"""Native llama provider against the pinned provider's public library API.

Build tests/llama-provider.bend to build/llama-provider(.js), then run here.
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
CATALOG = {"data": [
    {"id": "loaded", "status": {"value": "loaded"}, "architecture": {"input_modalities": ["text", "image"]}, "meta": {"n_ctx": 65536, "n_ctx_train": 131072}},
    {"id": "sleeping", "status": {"value": "sleeping"}, "meta": {"n_ctx": 0, "n_ctx_train": 32768}},
    {"id": "preset", "status": {"value": "unloaded"}, "source": "preset", "meta": {"n_ctx_train": 32768}},
    {"id": "failed-preset", "status": {"value": "unloaded", "failed": True}, "source": "preset"},
    {"id": "cache", "status": {"value": "unloaded"}, "source": "cache"},
    {"id": "loading", "status": {"value": "loading"}},
]}


class Router(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.server.requests.append((self.path, self.headers.get("Authorization")))
        path = urllib.parse.urlsplit(self.path)
        if path.path == "/models":
            value = self.server.catalog
        elif path.path == "/props" and not path.query:
            value = {"models_autoload": self.server.mode != "noautoload"}
        elif path.path == "/props":
            assert urllib.parse.parse_qs(path.query) == {"model": ["loaded"], "autoload": ["false"]}
            value = {"chat_template": "enable_thinking" if self.server.mode == "thinking" else "ordinary template"}
        else:
            self.send_error(404)
            return
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run(argv, mode, env=None, variant=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Router)
    server.requests = []
    server.mode = variant or mode
    server.catalog = {"data": CATALOG["data"][:1]} if mode == "thinking" else CATALOG
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}"
        result = subprocess.run([*argv, base, mode, json.dumps(server.catalog)], cwd=ROOT, env=env,
            capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, (argv, mode, result.stdout, result.stderr)
        assert not result.stderr, result.stderr
        def decoded(line):
            line = line.replace(base, "<server>")
            return json.loads(line) if line.startswith("{") else line
        return [decoded(line) for line in result.stdout.splitlines()], sorted(server.requests)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    lanes = []
    if args.backend in ("bun", "all"):
        lanes.append(("bun", ["bun", "build/llama-provider.js"], os.environ.copy()))
    if args.backend in ("native", "all"):
        lanes.extend((f"native{n}", [str(ROOT / "build/llama-provider")], {**os.environ, "BEND_THREADS": str(n)}) for n in (1, 4))
    for mode, variant in [(m, None) for m in ("catalog", "autoload", "thinking", "resolve", "login", "refresh", "cached")] + [("refresh", "noautoload")]:
        expected = run(["bun", "tests/llama_provider_reference.ts"], mode, variant=variant)
        for name, argv, env in lanes:
            actual = run(argv, mode, env, variant)
            assert actual == expected, (name, mode, actual, expected)
            print(f"{name}: {variant or mode} models/auth/prompts/requests MATCH")


if __name__ == "__main__":
    main()
