"""Local streaming fixture. Never contacts a provider or loads credentials."""
import http.server
import subprocess
import threading
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        assert body == b"{}"
        self.send_response(201)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for byte in 'data: {"text":"😃"}\r\n\r\n'.encode():
            self.wfile.write(bytes([byte]))
            self.wfile.flush()
            time.sleep(0.002)

    def log_message(self, *_):
        pass


with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    subprocess.run(["build/test-runtime", f"http://127.0.0.1:{server.server_port}"], check=True, timeout=15)
    server.shutdown()
