#!/usr/bin/env python3
"""Exercise the interactive startup catalog refresh through a loopback pi.dev proxy."""
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/parity"))
import runner  # noqa: E402

BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli")).resolve()


def certificate(directory):
    def openssl(*args):
        subprocess.run(["openssl", *args], cwd=directory, check=True, capture_output=True)

    curve = ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes"]
    openssl("req", "-x509", *curve, "-keyout", "ca.key", "-out", "ca.pem", "-days", "2",
            "-subj", "/CN=pi catalog test CA", "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign")
    openssl("req", *curve, "-keyout", "server.key", "-out", "server.csr", "-subj", "/CN=pi.dev")
    (directory / "server.ext").write_text("subjectAltName=DNS:pi.dev\nextendedKeyUsage=serverAuth\n")
    openssl("x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
            "-CAcreateserial", "-out", "server.pem", "-days", "2", "-extfile", "server.ext")
    return directory / "ca.pem", directory / "server.pem", directory / "server.key"


def model():
    return {"id": "startup-only", "name": "startup-only", "api": "openai-responses", "provider": "openai",
            "baseUrl": "https://api.openai.com/v1", "reasoning": False, "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 1000, "maxTokens": 100}


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_CONNECT(self):
        if self.path != "pi.dev:443":
            self.send_error(502)
            return
        self.send_response(200, "Connection Established")
        self.end_headers()
        self.connection = self.server.context.wrap_socket(self.connection, server_side=True)
        self.rfile = self.connection.makefile("rb", self.rbufsize)
        self.wfile = self.connection.makefile("wb", self.wbufsize)
        self.raw_requestline = self.rfile.readline(65537)
        if self.parse_request():
            self.do_GET()

    def do_GET(self):
        self.server.calls.append(self.path)
        self.server.seen.set()
        if self.server.stall:
            self.server.release.wait(20)
        if self.path == "/api/models/providers/openai":
            status, body = 200, json.dumps({"startup-only": model()}).encode()
        else:
            status, body = 404, b"not found"
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


def proxy(cert, key, stall):
    server = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
    server.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server.context.load_cert_chain(cert, key)
    server.calls = []
    server.seen = threading.Event()
    server.release = threading.Event()
    server.stall = stall
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def run_case(ca, cert, key, threads, offline=False, stall=False):
    with tempfile.TemporaryDirectory(prefix="pi-catalog-startup-") as place:
        root = Path(place)
        agent = root / "home/.pi/agent"
        project = root / "project"
        agent.mkdir(parents=True)
        project.mkdir()
        (agent / "models.json").write_text("{}")
        server = proxy(cert, key, stall)
        env = {"HOME": str(root / "home"), "PI_CODING_AGENT_DIR": str(agent), "PATH": os.environ["PATH"],
               "TERM": "xterm-256color", "LANG": "C.UTF-8", "OPENAI_API_KEY": "test-only-key",
               "PI_SKIP_VERSION_CHECK": "1", "BEND_THREADS": str(threads), "SSL_CERT_FILE": str(ca),
               "HTTPS_PROXY": f"http://127.0.0.1:{server.server_port}", "NO_PROXY": "127.0.0.1,localhost",
               **runner.package_links()}
        if offline:
            env["PI_OFFLINE"] = "1"
        terminal = runner.Terminal(f"pi-catalog-{threads}-{int(offline)}-{int(stall)}", [str(BINARY), "--provider", "openai", "--model", "gpt-5"], env, project)
        try:
            assert terminal.wait(r"gpt-5 • ", 15) is not None, terminal.screen()
            if offline:
                time.sleep(.3)
                assert not server.calls, server.calls
            else:
                assert server.seen.wait(10), (server.calls, terminal.screen())
                assert "/api/models/providers/openai" in server.calls, server.calls
                if stall:
                    started = time.monotonic()
                    terminal.key("C-d")
                    assert terminal.wait("shell\\$", 3) is not None, terminal.screen()
                    assert time.monotonic() - started < 3, "exit waited for stalled catalog fetch"
                else:
                    store = agent / "models-store.json"
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline and (not store.exists() or "startup-only" not in store.read_text()):
                        time.sleep(.02)
                    assert store.exists() and "startup-only" in store.read_text(), (server.calls, terminal.screen())
            if not stall:
                terminal.key("C-d")
                assert terminal.wait("shell\\$", 5) is not None, terminal.screen()
        finally:
            server.release.set()
            terminal.close()
            server.shutdown()


def main():
    with tempfile.TemporaryDirectory(prefix="pi-catalog-cert-") as place:
        ca, cert, key = certificate(Path(place))
        for threads in (1, 4):
            run_case(ca, cert, key, threads)
            run_case(ca, cert, key, threads, offline=True)
            run_case(ca, cert, key, threads, stall=True)
            print(f"native{threads}: startup fetch, offline skip, and stalled exit", flush=True)


if __name__ == "__main__":
    main()
