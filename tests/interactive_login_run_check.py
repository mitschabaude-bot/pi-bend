#!/usr/bin/env python3
"""Mounted native /login against loopback Codex device auth, including Esc cancellation."""
from upstream_pin import UPSTREAM
import errno
import base64
import fcntl
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import pty
import re
import select
import socket
import struct
import subprocess
import tempfile
import termios
import threading
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
BINARY = Path(os.environ.get("PI_BEND_LOGIN_RUN", ROOT / "build/interactive-login-run")).resolve()
payload = {"https://api.openai.com/auth": {"chatgpt_account_id": "acct_test"}}
segment = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
access = f"x.{segment}.x"

class Handler(BaseHTTPRequestHandler):
    generation = 0
    seen = []
    authorized = threading.Event()
    def log_message(self, *_):
        pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0))).decode()
        Handler.seen.append((Handler.generation, self.path, body))
        if self.path == "/usercode":
            Handler.generation += 1
            status, data = 200, {"device_auth_id": f"device_{Handler.generation}", "user_code": "ABCD-EFGH", "interval": "1"}
        elif self.path == "/token":
            if Handler.generation != 1:
                assert Handler.authorized.wait(20), "Device code was not presented to the user"
            status, data = (403, {"error": "deviceauth_authorization_pending"}) if Handler.generation == 1 else (200, {"authorization_code": "auth_test", "code_verifier": "verifier_test"})
        elif self.path == "/exchange":
            status, data = 200, {"access_token": access, "refresh_token": "refresh_test", "expires_in": 3600}
        elif self.path == "/anthropic-token":
            request = json.loads(body)
            assert request["grant_type"] == "authorization_code"
            assert request["code"] == "anthropic_test"
            assert request["state"] == request["code_verifier"]
            access_token = "anthropic_access_manual" if [item[1] for item in Handler.seen].count("/anthropic-token") == 2 else "anthropic_access"
            status, data = 200, {"access_token": access_token, "refresh_token": "anthropic_refresh", "expires_in": 3600}
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
    Handler.authorized.clear()
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
                until(b"no-model")
                before = len(output)
                os.write(master, b"/login openai-codex\r")
                until(b"Select OpenAI Codex login method:", before)
                os.write(master, b"\x1b[B\r")
                until(b"ABCD-EFGH", before)
                os.write(master, b"\x1b")
                until(b"Login cancelled", before)
                before = len(output)
                os.write(master, b"/login\r")
                until(b"Select authentication method", before)
                os.write(master, b"\r")
                until(b"Select provider to configure", before)
                os.write(master, b"\r")
                until(b"Select OpenAI Codex login method:", before)
                os.write(master, b"\x1b[B\r")
                until(b"ABCD-EFGH", before)
                Handler.authorized.set()
                until(b"Logged in to OpenAI Codex. Selected gpt-5.5", before)
                before = len(output)
                os.write(master, b"/model\r")
                until(b"gpt-5.5", before)
                until(b"[openai-codex]", before)
                saved = json.loads((agent_dir / "auth.json").read_text())["openai-codex"]
                assert saved["access"] == access and saved["refresh"] == "refresh_test"
                assert [item[1] for item in Handler.seen].count("/usercode") == 2
                assert any(item[1] == "/exchange" for item in Handler.seen)
                os.write(master, b"\x1b")
                time.sleep(.3)
                at = len(output)
                os.write(master, b"/login openai-codex\r")
                until(b"Select OpenAI Codex login method:", at)
                os.write(master, b"\r")
                until(b"Complete login in your browser", at)
                links = re.findall(rb"\x1b\]8;;(https://auth\.openai\.com/oauth/authorize\?[^\x07]*)\x07", output[at:])
                assert links, bytes(output[at:][-1800:])
                browser_params = urllib.parse.parse_qs(urllib.parse.urlparse(links[-1].decode()).query)
                state = browser_params["state"][0]
                assert len(state) == 32 and all(c in "0123456789abcdef" for c in state)
                assert browser_params["redirect_uri"] == ["http://localhost:1455/auth/callback"]
                exchanges = sum(path == "/exchange" for _, path, _ in Handler.seen)
                def codex_callback(given_state):
                    with socket.create_connection(("127.0.0.1", 1455), timeout=3) as connection:
                        connection.sendall(f"GET /auth/callback?code=browser_test&state={given_state} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode())
                        chunks = []
                        while chunk := connection.recv(4096):
                            chunks.append(chunk)
                        return b"".join(chunks)
                assert codex_callback("wrong").startswith(b"HTTP/1.1 400 Bad Request")
                assert codex_callback(state).startswith(b"HTTP/1.1 200 OK")
                deadline = time.monotonic() + 20
                while sum(path == "/exchange" for _, path, _ in Handler.seen) == exchanges:
                    assert time.monotonic() < deadline, "Browser code was not exchanged"
                    if select.select([master], [], [], .05)[0]:
                        output.extend(os.read(master, 65536))
                body = next(body for _, path, body in reversed(Handler.seen) if path == "/exchange")
                exchange = urllib.parse.parse_qs(body)
                assert exchange["code"] == ["browser_test"]
                assert exchange["redirect_uri"] == ["http://localhost:1455/auth/callback"]
                verifier = exchange["code_verifier"][0]
                expected_challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
                assert browser_params["code_challenge"] == [expected_challenge]
                # Let the model synchronization close the dialog before typing.
                time.sleep(.3)
                at = len(output)
                os.write(master, b"hello after login\r")
                until(b"answer", at)
                at = len(output)
                os.write(master, b"/login\r")
                until(b"Select authentication method", at)
                os.write(master, b"\r")
                until(b"Select provider to configure", at)
                os.write(master, b"\x1b[B\r")
                until(b"Complete login in your browser, or paste", at)
                links = re.findall(rb"\x1b\]8;;(https://claude\.ai/oauth/authorize\?[^\x07]*)\x07", output[at:])
                assert links, bytes(output[at:][-1800:])
                link = links[-1].decode()
                params = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)
                assert "state" in params, link
                state = params["state"][0]
                def callback(given_state):
                    with socket.create_connection(("127.0.0.1", 53692), timeout=3) as connection:
                        connection.sendall(f"GET /callback?code=anthropic_test&state={given_state} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode())
                        chunks = []
                        while chunk := connection.recv(4096):
                            chunks.append(chunk)
                        return b"".join(chunks)
                assert callback("wrong").startswith(b"HTTP/1.1 400 Bad Request")
                assert callback(state).startswith(b"HTTP/1.1 200 OK")
                until(b"Logged in to Anthropic", at)
                with socket.socket() as occupied:
                    occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    occupied.bind(("127.0.0.1", 53692))
                    occupied.listen()
                    at = len(output)
                    os.write(master, b"/login anthropic\r")
                    until(b"Complete login in your browser, or paste", at)
                    os.write(master, b"\x1b[200~anthropic_test\x1b[201~\r")
                    # The repeated success notice can remain unchanged on screen;
                    # distinguish this exchange by its newly stored access token.
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        credentials = json.loads((agent_dir / "auth.json").read_text())
                        if credentials.get("anthropic", {}).get("access") == "anthropic_access_manual":
                            break
                        if select.select([master], [], [], .05)[0]:
                            output.extend(os.read(master, 65536))
                    assert credentials.get("anthropic", {}).get("access") == "anthropic_access_manual"
                at = len(output)
                os.write(master, b"/model\r")
                until(b"claude", at)
                until(b"[anthropic]", at)
                anthropic = json.loads((agent_dir / "auth.json").read_text())["anthropic"]
                assert anthropic["access"] == "anthropic_access_manual" and anthropic["refresh"] == "anthropic_refresh"
                assert [item[1] for item in Handler.seen].count("/anthropic-token") == 2
                os.write(master, b"\x1b")
                time.sleep(.3)
                at = len(output)
                os.write(master, b"/logout\r")
                until(b"Stored credentials", at)
                until(b"OpenAI Codex", at)
                until(b"Anthropic", at)
                os.write(master, b"anthropic")
                time.sleep(.2)
                os.write(master, b"\r")
                until(b"Logged out of Anthropic", at)
                remaining = json.loads((agent_dir / "auth.json").read_text())
                assert "anthropic" not in remaining and "openai-codex" in remaining
                at = len(output)
                os.write(master, b"/logout\r")
                until(b"Stored credentials", at)
                os.write(master, b"\x1b")
                assert "openai-codex" in json.loads((agent_dir / "auth.json").read_text())
                time.sleep(.2)
                at = len(output)
                os.write(master, b"/logout\r")
                until(b"Stored credentials", at)
                os.write(master, b"\r")
                until(b"Logged out of OpenAI Codex", at)
                assert json.loads((agent_dir / "auth.json").read_text()) == {}
                at = len(output)
                os.write(master, b"/logout\r")
                until(b"No stored credentials to remove", at)
                at = len(output)
                os.write(master, b"/login missing-provider\r")
                until(b"Unknown login provider: missing-provider", at)
                at = len(output)
                os.write(master, b"/hotkeys\r")
                until(b"Move by word", at)
                until(b"Run bash command", at)
                os.write(master, b"/quit\r")
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
    print(f"native{threads}: model-free Codex browser/device and Anthropic browser/manual login, cancellation, saved credentials, model selection and logout")

for threads in (1, 4):
    scenario(threads)
