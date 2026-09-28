#!/usr/bin/env python3
"""Exercise the native Radius upload against a loopback HTTP server."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build/session-share-radius"
CONTENT = '{"type":"session","id":"π"}\n'


class Handler(BaseHTTPRequestHandler):
    reply = (201, {"artifact": {"canonical_url": "https://radius.test/a/123"}})
    calls = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.calls.append((self.path, self.headers, body))
        payload = json.dumps(self.reply[1]).encode()
        self.send_response(self.reply[0])
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    url = f"http://127.0.0.1:{server.server_port}/v1/artifacts?visibility=organization&title=Pi+session"
    for workers in (1, 4):
        for status, payload, expected in (
            (201, {"artifact": {"canonical_url": "https://radius.test/a/123"}}, "SHARED https://radius.test/a/123"),
            (403, {"error": "access denied"}, "FAILED Failed to upload Radius artifact: access denied"),
            (200, {}, "FAILED Failed to upload Radius artifact: 200"),
        ):
            Handler.reply = status, payload
            result = subprocess.run(
                [str(BINARY), "--threads", str(workers), url, "fixture-token", CONTENT],
                cwd=ROOT, capture_output=True, text=True, timeout=20, check=True,
            )
            assert result.stdout.strip() == expected, result.stdout + result.stderr
            path, headers, body = Handler.calls[-1]
            assert path == "/v1/artifacts?visibility=organization&title=Pi+session"
            assert headers["Authorization"] == "Bearer fixture-token"
            assert headers["Content-Type"] == "application/x-ndjson"
            assert int(headers["Content-Length"]) == len(CONTENT.encode())
            assert body == CONTENT.encode()
        print(f"native{workers}: Radius request, success, rejection and missing artifact")
finally:
    server.shutdown()
    server.server_close()
