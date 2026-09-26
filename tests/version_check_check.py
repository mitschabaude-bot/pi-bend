"""upstream version-check.test.ts and pi-user-agent.test.ts on Bun/native lanes.

tests/version-check.bend sends the library's https://pi.dev requests through a
logging fetch to this local server; the first path segment picks the answer.
Usage: python3 tests/version_check_check.py [build/version-check.js] [build/version-check]
"""
import http.server, json, os, pathlib, platform, socketserver, subprocess, sys, threading

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/version-check.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/version-check'
answers = {
    'same': {'version': '1.2.3'},
    'ua': {'version': '1.2.4'},
    'flaky': {'version': '1.2.4'},
    'meta': {'packageName': '@new-scope/pi', 'version': '1.2.4'},
    'note': {'note': ' **Read this** ', 'version': '1.2.4'},
}
state = {'flaky': 0}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        route = self.path.split('/')[1]
        assert self.path == f'/{route}/api/latest-version', self.path
        if route == 'down' or (route == 'flaky' and state['flaky'] < 2):
            state['flaky'] += route == 'flaky'
            self.close_connection = True
            self.connection.close()
            return
        body = json.dumps(answers[route]).encode()
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


node_platform = {'Linux': 'linux', 'Darwin': 'darwin'}[platform.system()]
node_arch = {'x86_64': 'x64', 'aarch64': 'arm64'}[platform.machine()]
lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/version-check.bend first'
for name, command in lanes:
    state['flaky'] = 0
    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        env = {k: v for k, v in os.environ.items() if k not in ('PI_OFFLINE', 'PI_SKIP_VERSION_CHECK')}
        result = subprocess.run(command + [f'http://127.0.0.1:{server.server_address[1]}', node_platform, node_arch], cwd=root, capture_output=True, text=True, timeout=120, env=env)
    finally:
        server.shutdown()
    lines = result.stdout.splitlines()
    assert result.returncode == 0 and len(lines) == 10 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr)
    print(f'{name}: {len(lines)} version-check/pi-user-agent cases pass')
