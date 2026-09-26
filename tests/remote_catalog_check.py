"""upstream remote-catalog-provider.test.ts (tests/remote-catalog.bend) on Bun/native lanes.

The provider's https://pi.dev catalog requests reach this server through a
logging redirect fetch; the first path segment names the case, whose
responses are served in order (upstream's mocked fetch sequences).
Usage: python3 tests/remote_catalog_check.py [build/remote-catalog.js] [build/remote-catalog]
"""
import calendar, email.utils, http.server, json, os, pathlib, socketserver, subprocess, sys, threading

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/remote-catalog.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/remote-catalog'
LOCAL = calendar.timegm((2026, 7, 23, 10, 0, 0))


def model(id):
    return {'id': id, 'name': id, 'api': 'openai-completions', 'provider': 'test-provider', 'baseUrl': 'https://example.test/v1',
            'reasoning': False, 'input': ['text'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
            'contextWindow': 1000, 'maxTokens': 100}


def ok(body, **headers):
    return (200, json.dumps(body).encode(), dict({'content-type': 'application/json'}, **headers))


def http_date(seconds):
    return email.utils.formatdate(seconds, usegmt=True)


def sequences():
    return {
        'keyed': [ok({'dynamic': model('dynamic')})] * 5,
        'newer': [ok({'old': model('old')}, **{'last-modified': http_date(LOCAL - 60)}), ok({'newer': model('newer')}, **{'last-modified': http_date(LOCAL + 60)})],
        'etag': [ok({'dynamic': model('dynamic')}, etag='"catalog-1"'), (304, b'', {'etag': '"catalog-1"'})],
        'stale': [ok({'dynamic': model('dynamic')}, etag='"catalog-1"'), (501, b'not implemented', {})],
        'transient': [ok({'dynamic': model('dynamic')}, etag='"catalog-1"')] + [(429, b'rate limited', {})] * 3 + [(304, b'', {'etag': '"catalog-1"'})],
        'unimplemented': [(501, b'not implemented', {})] * 3,
    }


queues = {}
stall_state = {'seen': False}
second_answered = threading.Event()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        case = self.path.split('/')[1]
        assert self.path == f'/{case}/api/models/providers/test-provider', self.path
        if case == 'stall':
            self.stall()
            return
        code, body, headers = queues[case].pop(0)
        self.answer(code, body, headers)

    # The first request waits until the second has been answered.
    def stall(self):
        first = not stall_state['seen']
        stall_state['seen'] = True
        if first:
            second_answered.wait(60)
            self.answer(*ok({'older': model('older')}))
        else:
            self.answer(*ok({'newer': model('newer')}))
            second_answered.set()

    def answer(self, code, body, headers):
        self.send_response(code)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass  # the client resets connections whose bodies it discards


lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/remote-catalog.bend first'
for name, command in lanes:
    queues.clear()
    queues.update(sequences())
    second_answered.clear()
    stall_state['seen'] = False
    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        result = subprocess.run(command + [f'http://127.0.0.1:{server.server_address[1]}', str(LOCAL)], cwd=root, capture_output=True, text=True, timeout=300, env=dict({k: v for k, v in os.environ.items() if k != 'PI_OFFLINE'}, TEST_PROVIDER_KEY='test-key'))
    finally:
        server.shutdown()
    lines = result.stdout.splitlines()
    assert result.returncode == 0 and len(lines) == 7 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr[-3000:])
    print(f'{name}: {len(lines)} remote catalog cases pass')
