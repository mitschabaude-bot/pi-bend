"""A loopback HTTPS endpoint reached through CONNECT as radius.pi.dev."""
import json
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_CONNECT(self):
        if self.path != "radius.pi.dev:443":
            self.send_error(502)
            return
        self.send_response(200, "Connection Established")
        self.end_headers()
        self.connection = self.server.context.wrap_socket(self.connection, server_side=True)
        self.rfile = self.connection.makefile("rb", self.rbufsize)
        self.wfile = self.connection.makefile("wb", self.wbufsize)
        self.raw_requestline = self.rfile.readline(65537)
        if self.parse_request():
            self.do_POST()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.calls.append((self.path, dict(self.headers), body))
        time.sleep(self.server.delay)
        payload = json.dumps({"artifact": {"canonical_url": "https://radius.pi.dev/a/fixture"}}).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


def serve(cert, delay=0):
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server.context.load_cert_chain(*cert)
    server.calls = []
    server.delay = delay
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
