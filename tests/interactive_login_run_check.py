#!/usr/bin/env python3
"""Mounted native /login against loopback Codex device auth, including Esc cancellation."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
BINARY = Path(os.environ.get("PI_BEND_NEW_RUN", ROOT / "build/interactive-new-run")).resolve()


import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BINARY = Path(os.environ.get("PI_BEND_LOGIN_RUN", ROOT / "build/interactive-login-run")).resolve()
payload = {"https://api.openai.com/auth": {"chatgpt_account_id": "acct_test"}}
segment = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
access = f"x.{segment}.x"

class Handler(BaseHTTPRequestHandler):
    generation = 0
    seen = []
    def log_message(self, *_):
        pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0))).decode()
        Handler.seen.append((Handler.generation, self.path, body))
        if self.path == "/usercode":
            Handler.generation += 1
            status, data = 200, {"device_auth_id": f"device_{Handler.generation}", "user_code": "ABCD-EFGH", "interval": "1"}
        elif self.path == "/token":
            status, data = (403, {"error": "deviceauth_authorization_pending"}) if Handler.generation == 1 else (200, {"authorization_code": "auth_test", "code_verifier": "verifier_test"})
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

def scenario(threads):
    Handler.generation = 0
    Handler.seen = []
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
        original = termios.tcgetattr(slave)
        with tempfile.TemporaryDirectory(prefix="pi-interactive-login-") as place:
            cwd = Path(place)
            agent_dir = cwd / "agent"
            process = subprocess.Popen(
                [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, str(agent_dir), f"http://127.0.0.1:{server.server_port}"],
                cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
                env={**os.environ, "TERM": "xterm-256color", "PI_CODING_AGENT_DIR": str(agent_dir)},
            )
            output = bytearray()
            def until(needle, start=0, timeout=20):
                deadline = time.monotonic() + timeout
                while needle not in output[start:] and time.monotonic() < deadline:
                    if select.select([master], [], [], .2)[0]:
                        try:
                            output.extend(os.read(master, 65536))
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                            break
                assert needle in output[start:], (threads, needle, process.poll(), Handler.seen[-8:], bytes(output[start:][-1800:]))
            try:
                until(b"faux-model")
                before = len(output)
                os.write(master, b"/login\r")
                until(b"ABCD-EFGH", before)
                os.write(master, b"\x1b")
                until(b"Login cancelled", before)
                before = len(output)
                os.write(master, b"/login\r")
                until(b"ABCD-EFGH", before)
                until(b"Logged in to OpenAI Codex", before)
                before = len(output)
                os.write(master, b"/model\r")
                until(b"openai-codex/gpt", before)
                saved = json.loads((agent_dir / "auth.json").read_text())["openai-codex"]
                assert saved["access"] == access and saved["refresh"] == "refresh_test"
                assert [item[1] for item in Handler.seen].count("/usercode") == 2
                assert any(item[1] == "/exchange" for item in Handler.seen)
                os.write(master, b"\x1b")
                time.sleep(.3)
                at = len(output)
                os.write(master, b"/help\r")
                until(b"Commands: /model [search]", at)
                os.write(master, b"/exit\r")
                stderr = process.communicate(timeout=20)[1]
                assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
                assert termios.tcgetattr(slave) == original
                assert not stderr, (threads, stderr.decode(errors="replace"))
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                os.close(master)
                os.close(slave)
        server.shutdown()
    print(f"native{threads}: mounted /login device code, Esc cancellation, auth.json, refreshed /model")

for threads in (1, 4):
    scenario(threads)
