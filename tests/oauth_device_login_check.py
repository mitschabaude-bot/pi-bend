#!/usr/bin/env python3
"""Exercise native Codex device login and auth.json persistence against loopback HTTP.

Pinned to pi-mono 46c9de402, packages/ai/test/openai-codex-oauth.test.ts:
device code notice, pending poll, authorization-code exchange, and account claim.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

payload = {"https://api.openai.com/auth": {"chatgpt_account_id": "acct_test"}}
segment = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
access = f"x.{segment}.x"

class Handler(BaseHTTPRequestHandler):
    polls = 0
    seen = []

    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length).decode()
        self.seen.append((self.path, self.headers.get("content-type"), body))
        if self.path == "/usercode":
            status, data = 200, {"device_auth_id": "device_test", "user_code": "ABCD-EFGH", "interval": "0"}
        elif self.path == "/token":
            Handler.polls += 1
            status, data = (403, {"error": "deviceauth_authorization_pending"}) if Handler.polls == 1 else (200, {"authorization_code": "auth_test", "code_verifier": "verifier_test"})
        elif self.path == "/exchange":
            status, data = 200, {"access_token": access, "refresh_token": "refresh_test", "expires_in": 3600}
        else:
            status, data = 404, {"error": "bad path"}
        wire = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(wire)))
        self.end_headers()
        self.wfile.write(wire)

with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server, tempfile.TemporaryDirectory() as directory:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    env = os.environ.copy()
    env["PI_CODING_AGENT_DIR"] = directory
    command = sys.argv[1:] + [origin]
    try:
        completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
    except subprocess.TimeoutExpired as error:
        raise AssertionError((Handler.seen, error.stdout, error.stderr)) from error
    assert completed.returncode == 0, (completed.stdout, completed.stderr)
    assert "ABCD-EFGH" in completed.stdout and "/codex/device" in completed.stdout
    assert "Logged in to OpenAI Codex" in completed.stdout
    saved = json.loads((Path(directory) / "auth.json").read_text())["openai-codex"]
    assert saved["type"] == "oauth" and saved["access"] == access
    assert saved["refresh"] == "refresh_test" and saved["accountId"] == "acct_test"
    assert (Path(directory) / "auth.json").stat().st_mode & 0o777 == 0o600
    assert [item[0] for item in Handler.seen] == ["/usercode", "/token", "/token", "/exchange"]
    assert json.loads(Handler.seen[0][2]) == {"client_id": "app_EMoamEEZ73f0CkXaXp7hrann"}
    assert json.loads(Handler.seen[1][2]) == {"device_auth_id": "device_test", "user_code": "ABCD-EFGH"}
    assert "grant_type=authorization_code" in Handler.seen[-1][2]
    assert "code_verifier=verifier_test" in Handler.seen[-1][2]
    assert "redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback" in Handler.seen[-1][2]
    print("device login and auth.json persistence passed")
    server.shutdown()
