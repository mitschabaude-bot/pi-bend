"""upstream tools-manager.test.ts (tests/tools-manager-latest.bend) on Bun/native lanes.

A local server answers the library's github.com requests per repository path
(release redirects, a redirect with a body, 404, a redirect to /login); the
ensureTool case runs offline with an empty bin directory and PATH, so fd is
missing as upstream's mocked existsSync/spawnSync make it.
Usage: python3 tests/tools_manager_latest_check.py [build/tools-manager-latest.js] [build/tools-manager-latest]
"""
import http.server, os, pathlib, socketserver, subprocess, sys, tempfile, threading

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/tools-manager-latest.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/tools-manager-latest'
ROUTES = {
    '/sharkdp/fd/releases/latest': (302, 'https://github.com/sharkdp/fd/releases/tag/v10.4.2', b''),
    '/BurntSushi/ripgrep/releases/latest': (302, 'https://github.com/BurntSushi/ripgrep/releases/tag/15.2.0', b''),
    '/relative/fd/releases/latest': (302, '/sharkdp/fd/releases/tag/v10.4.2', b''),
    '/body/fd/releases/latest': (302, 'https://github.com/sharkdp/fd/releases/tag/v10.4.2', b'<html></html>'),
    '/missing/fd/releases/latest': (404, None, b'not found'),
    '/login/fd/releases/latest': (302, 'https://github.com/login', b''),
}
served = []


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        served.append((self.path, self.headers.get('user-agent')))
        code, location, body = ROUTES[self.path]
        self.send_response(code)
        if location is not None:
            self.send_header('location', location)
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass  # the client resets connections whose redirect body it discards


lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/tools-manager-latest.bend first'
for name, command in lanes:
    served.clear()
    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory(prefix='pi-tools-') as directory:
        env = {k: v for k, v in os.environ.items() if k != 'PI_OFFLINE'}
        env['PATH'] = directory
        exe = command[0] if command[0] != 'bun' else subprocess.check_output(['which', 'bun'], text=True).strip()
        try:
            result = subprocess.run([exe] + command[1:] + [f'http://127.0.0.1:{server.server_address[1]}', directory], cwd=root, capture_output=True, text=True, timeout=120, env=env)
        finally:
            server.shutdown()
    lines = result.stdout.splitlines()
    assert result.returncode == 0 and len(lines) == 7 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr)
    assert all(agent == 'pi-coding-agent' for _, agent in served) and len(served) == 6, served
    print(f'{name}: {len(lines)} tools-manager cases pass')
