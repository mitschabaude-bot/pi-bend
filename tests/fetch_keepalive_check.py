"""HTTP keep-alive in runtime/fetch against a local HTTP/1.1 server.

Mirrors undici's Agent as bundled with Node 24: a fully read HTTP/1.1
response parks its connection for the next request to the same origin
(4 s idle, or a Keep-Alive timeout hint minus 2 s), `Connection: close` and
too-short hints prevent reuse, and an idle socket the server closed is
discarded before reuse instead of failing the next request.
"""
import argparse, http.server, socket, subprocess, threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, behaviour):
        self.behaviour = behaviour; self.connections = 0; self.requests = 0
        super().__init__(('127.0.0.1', 0), Handler)
    def process_request(self, request, address):
        self.connections += 1
        super().process_request(request, address)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def setup(self):
        idle = self.server.behaviour.get('idle')
        if idle is not None: self.timeout = idle
        super().setup()
    def do_GET(self):
        self.server.requests += 1
        body = ('hello %d' % self.server.requests).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        for name, value in self.server.behaviour.get('headers', []): self.send_header(name, value)
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass

def scenario(command, behaviour, count, pause):
    server = Server(behaviour); thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    try:
        url = 'http://127.0.0.1:%d/' % server.server_address[1]
        result = subprocess.run(command + [url, str(count), str(pause)], capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stderr[-1500:]
        lines = result.stdout.strip().splitlines()
        assert lines == ['200 hello %d' % i for i in range(1, count + 1)], lines
        return server.connections
    finally:
        server.shutdown(); server.server_close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/fetch-keepalive.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    checks = [
        ('persistent responses reuse one connection', {}, 3, 0, 1),
        ('Connection: close prevents reuse', {'headers': [('Connection', 'close')]}, 3, 0, 3),
        ('a Keep-Alive hint of 2 s or less prevents reuse', {'headers': [('Keep-Alive', 'timeout=2')]}, 3, 0, 3),
        ('a longer Keep-Alive hint allows reuse', {'headers': [('Keep-Alive', 'timeout=5, max=100')]}, 3, 0, 1),
        ('an idle socket the server closed is replaced', {'idle': 0.2}, 3, 600, 3),
        ('connections idle past 4 s are not reused', {}, 2, 4300, 2),
    ]
    for label, behaviour, count, pause, expected in checks:
        connections = scenario(command, behaviour, count, pause)
        assert connections == expected, (label, connections, expected)
        print('PASS', label)
    print('fetch-keepalive: %d checks passed' % len(checks))

main()
