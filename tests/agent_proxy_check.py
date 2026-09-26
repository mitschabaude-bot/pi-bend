#!/usr/bin/env python3
"""upstream packages/agent/test/proxy.test.ts over the native streamProxy.

Upstream stubs the global fetch with a Response holding each test's body.
Here each case starts a loopback server that answers POST /api/stream with
that body, runs packages/agent/test/proxy.bend on the selected backends,
asserts the upstream expectations, and compares the whole event trace, the
result and the request with upstream proxy.ts reading the same server
(packages/agent/test/proxy-oracle.ts). The three named upstream cases come
first; the supplementary cases cover the rest of processProxyEvent and the
HTTP failure paths the same way. Timestamps are normalized, and upstream's
transient `partialJson` member of streaming tool calls is dropped (the port
keeps it beside the message).
"""
from upstream_pin import UPSTREAM
import argparse
import http.server
import json
import os
import pathlib
import re
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = 'packages/agent/test/proxy.bend'
ORACLE = ROOT / 'packages/agent/test/proxy-oracle.ts'

USAGE = {
    'input': 0,
    'output': 0,
    'cacheRead': 0,
    'cacheWrite': 0,
    'totalTokens': 0,
    'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0},
}
BILLED = {
    'input': 10,
    'output': 5,
    'cacheRead': 2,
    'cacheWrite': 1,
    'totalTokens': 18,
    'cost': {'input': 0.1, 'output': 0.2, 'cacheRead': 0.01, 'cacheWrite': 0.02, 'total': 0.33},
}


def data(event):
    return f'data: {json.dumps(event, ensure_ascii=False)}\n\n'


class Server:
    """Answers each POST with `status` and the body, written in `chunks`."""

    def __init__(self, chunks, status=200, reason=None, content_type='text/event-stream'):
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get('content-length', '0'))).decode()
                outer.requests.append({'url': self.path, 'headers': {k.lower(): v for k, v in self.headers.items()}, 'body': json.loads(raw) if raw else None})
                self.send_response(status, reason)
                self.send_header('content-type', content_type)
                self.send_header('transfer-encoding', 'chunked')
                self.send_header('connection', 'close')
                self.close_connection = True
                self.end_headers()
                for piece in chunks:
                    chunk = piece if isinstance(piece, bytes) else piece.encode()
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                    self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n')

            def log_message(self, *_):
                pass

        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f'http://127.0.0.1:{self.server.server_port}'

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()


def parse(output):
    lines = {'event': [], 'result': []}
    for line in output.splitlines():
        kind, _, rest = line.partition(' ')
        lines[kind].append(json.loads(rest))
    return lines


def run(command, base):
    result = subprocess.run([*command, 'proxy', base], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise AssertionError((command, result.returncode, result.stdout, result.stderr))
    return parse(result.stdout), result.stderr


def oracle(base):
    result = subprocess.run(['bun', str(ORACLE), base], capture_output=True, text=True, timeout=60, env=dict(os.environ, PI_MONO=str(UPSTREAM)))
    if result.returncode != 0:
        raise AssertionError(('oracle', result.stdout, result.stderr))
    return parse(result.stdout), result.stderr


def normalized(value):
    if isinstance(value, dict):
        return {k: ('<time>' if k == 'timestamp' else normalized(v)) for k, v in value.items() if k != 'partialJson'}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    return value


def warnings(stderr):
    return [line for line in stderr.splitlines() if line.startswith('Unhandled proxy event type')]


def types(lines):
    return [event['type'] for event in lines['event']]


# The named upstream cases
# ------------------------
def tool_call_metadata():
    events = [data(e) for e in [
        {'type': 'start'},
        {'type': 'toolcall_start', 'contentIndex': 0, 'id': 'call_test|fc_test', 'toolName': 'lookup'},
        {'type': 'toolcall_delta', 'contentIndex': 0, 'delta': '{"value":"hello"}'},
        {'type': 'toolcall_end', 'contentIndex': 0, 'toolCall': {'type': 'toolCall', 'id': 'call_test|fc_test', 'name': 'lookup', 'arguments': {'value': 'hello'}, 'namespace': 'dynamic_tools'}},
        {'type': 'done', 'reason': 'toolUse', 'usage': USAGE},
    ]]
    return [''.join(events)]


def check_tool_call_metadata(lines):
    end = next(e for e in lines['event'] if e['type'] == 'toolcall_end')
    assert end['toolCall']['namespace'] == 'dynamic_tools', end
    first = lines['result'][0]['content'][0]
    assert first['type'] == 'toolCall' and first['arguments'] == {'value': 'hello'} and first['namespace'] == 'dynamic_tools', first


def terminal_metadata():
    return [data({'type': 'start'}) + 'data: ' + json.dumps({'type': 'done', 'reason': 'stop', 'usage': USAGE, 'providerThinkingLevel': 'high'})]


def check_terminal_metadata(lines):
    assert types(lines) == ['start', 'done'], types(lines)
    assert lines['result'][0]['stopReason'] == 'stop'
    assert lines['result'][0]['providerThinkingLevel'] == 'high'


def unterminated():
    return [data({'type': 'start'})]


def check_unterminated(lines):
    assert types(lines) == ['start', 'error'], types(lines)
    assert lines['result'][0]['stopReason'] == 'error'
    assert 'Connection closed by proxy server' in lines['result'][0]['errorMessage']


NAMED = [
    ('preserves tool-call metadata received only on toolcall_end', tool_call_metadata, {}, check_tool_call_metadata),
    ('processes terminal metadata when the event is not newline-terminated', terminal_metadata, {}, check_terminal_metadata),
    ('emits an error instead of hanging when the stream ends without a terminal event', unterminated, {}, check_unterminated),
]


# Supplementary cases
# -------------------
def text_and_thinking():
    body = ''.join(data(e) for e in [
        {'type': 'start'},
        {'type': 'thinking_start', 'contentIndex': 0},
        {'type': 'thinking_delta', 'contentIndex': 0, 'delta': 'Let me '},
        {'type': 'thinking_delta', 'contentIndex': 0, 'delta': 'think'},
        {'type': 'thinking_end', 'contentIndex': 0, 'contentSignature': 'sig-think'},
        {'type': 'text_start', 'contentIndex': 1},
        {'type': 'text_delta', 'contentIndex': 1, 'delta': 'Grüße 🌍'},
        {'type': 'text_delta', 'contentIndex': 1, 'delta': ' done'},
        {'type': 'text_end', 'contentIndex': 1, 'contentSignature': 'sig-text'},
        {'type': 'done', 'reason': 'length', 'usage': BILLED, 'providerThinkingLevel': 'medium'},
    ]).encode()
    # Chunk boundaries fall inside the multi-byte characters and the lines.
    cut = [7, 31, body.index('🌍'.encode()) + 2, len(body) - 9]
    return [body[a:b] for a, b in zip([0] + cut, cut + [len(body)])]


def check_text_and_thinking(lines):
    result = lines['result'][0]
    assert result['stopReason'] == 'length' and result['usage'] == BILLED, result
    assert result['content'] == [
        {'type': 'thinking', 'thinking': 'Let me think', 'thinkingSignature': 'sig-think'},
        {'type': 'text', 'text': 'Grüße 🌍 done', 'textSignature': 'sig-text'},
    ], result['content']


def terminal_error():
    return [''.join(data(e) for e in [
        {'type': 'start'},
        {'type': 'text_start', 'contentIndex': 0},
        {'type': 'text_delta', 'contentIndex': 0, 'delta': 'partial answer'},
        {'type': 'error', 'reason': 'aborted', 'errorMessage': 'Request was aborted', 'usage': BILLED},
    ])]


def check_terminal_error(lines):
    assert types(lines)[-1] == 'error'
    result = lines['result'][0]
    assert result['stopReason'] == 'aborted' and result['errorMessage'] == 'Request was aborted', result
    assert result['content'] == [{'type': 'text', 'text': 'partial answer'}], result


def crlf_and_other_lines():
    # Comment and event lines are ignored, CRLF endings are trimmed, and an
    # empty data payload is skipped.
    return ['event: message\r\n: comment\r\n' + data({'type': 'start'}).replace('\n\n', '\r\n\r\n') + 'data: \n\n' + data({'type': 'done', 'reason': 'stop', 'usage': USAGE})]


def check_crlf(lines):
    assert types(lines) == ['start', 'done'], types(lines)


def unknown_and_stray_end():
    return [''.join(data(e) for e in [
        {'type': 'start'},
        {'type': 'mystery', 'contentIndex': 0},
        {'type': 'text_start', 'contentIndex': 0},
        {'type': 'toolcall_end', 'contentIndex': 0, 'toolCall': {'type': 'toolCall', 'id': 'x', 'name': 'y', 'arguments': {}}},
        {'type': 'text_end', 'contentIndex': 0},
        {'type': 'done', 'reason': 'stop', 'usage': USAGE},
    ])]


def check_unknown(lines):
    assert types(lines) == ['start', 'text_start', 'text_end', 'done'], types(lines)


def mismatched_delta():
    return [''.join(data(e) for e in [
        {'type': 'start'},
        {'type': 'text_start', 'contentIndex': 0},
        {'type': 'thinking_delta', 'contentIndex': 0, 'delta': 'x'},
        {'type': 'done', 'reason': 'stop', 'usage': USAGE},
    ])]


def check_mismatched(lines):
    assert types(lines) == ['start', 'text_start', 'error'], types(lines)
    result = lines['result'][0]
    assert result['stopReason'] == 'error' and result['errorMessage'] == 'Received thinking_delta for non-thinking content', result
    assert result['content'] == [{'type': 'text', 'text': ''}], result


def http_error_json():
    return [json.dumps({'error': 'Token expired'})]


def check_http_error_json(lines):
    assert types(lines) == ['error'], types(lines)
    assert lines['result'][0]['errorMessage'] == 'Proxy error: Token expired'


def http_error_plain():
    return ['upstream unavailable']


def check_http_error_plain(lines):
    assert types(lines) == ['error'], types(lines)
    assert lines['result'][0]['errorMessage'] == 'Proxy error: 502 Bad Gateway'


SUPPLEMENTARY = [
    ('text and thinking deltas split across chunks', text_and_thinking, {}, check_text_and_thinking),
    ('a terminal error event keeps the partial content', terminal_error, {}, check_terminal_error),
    ('non-data lines, CRLF endings and empty payloads', crlf_and_other_lines, {}, check_crlf),
    ('unknown event types and a toolcall_end for other content publish nothing', unknown_and_stray_end, {}, check_unknown),
    ('a delta for the wrong content type fails the stream', mismatched_delta, {}, check_mismatched),
    ('a failed response reports the JSON error', http_error_json, {'status': 401, 'content_type': 'application/json'}, check_http_error_json),
    ('a failed response without a JSON error reports the status', http_error_plain, {'status': 502, 'reason': 'Bad Gateway', 'content_type': 'text/plain'}, check_http_error_plain),
]


# upstream console.warn for an event type processProxyEvent does not handle.
WARNINGS = {'unknown event types and a toolcall_end for other content publish nothing': ['Unhandled proxy event type: mystery']}


def case(command, name, chunks, server_options, check):
    server = Server(chunks(), **server_options)
    with server as base:
        lines, stderr = run(command, base)
        reference, reference_stderr = oracle(base)
    check(lines)
    native = {'events': normalized(lines['event']), 'result': normalized(lines['result'])}
    upstream = {'events': normalized(reference['event']), 'result': normalized(reference['result'])}
    assert native == upstream, (name, json.dumps(native, indent=1), json.dumps(upstream, indent=1))
    assert warnings(stderr) == warnings(reference_stderr) == WARNINGS.get(name, []), (name, stderr, reference_stderr)
    assert len(server.requests) == 2, server.requests
    request, expected = server.requests
    assert request['url'] == '/api/stream' == expected['url'], (request['url'], expected['url'])
    assert request['headers']['authorization'] == 'Bearer test-token' == expected['headers']['authorization']
    assert request['headers']['content-type'] == expected['headers']['content-type']
    assert request['body'] == expected['body'], (name, request['body'], expected['body'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/agent-proxy')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--no-build', action='store_true')
    arguments = parser.parse_args()

    source = (UPSTREAM / 'packages/agent/test/proxy.test.ts').read_text()
    names = re.findall(r'^\s*it\("([^"]+)"', source, re.M)
    assert names == [name for name, *_ in NAMED], names

    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', SOURCE, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', SOURCE, arguments.prefix], cwd=ROOT, check=True)

    failures = 0
    for backend in arguments.backends:
        command = ['bun', str(ROOT / (arguments.prefix + '.js'))] if backend == 'bun' else [str(ROOT / arguments.prefix), '--threads', backend[-1]]
        for label, cases in [('upstream', NAMED), ('supplementary', SUPPLEMENTARY)]:
            passed = 0
            for name, chunks, server_options, check in cases:
                try:
                    case(command, name, chunks, server_options, check)
                    passed += 1
                except AssertionError as error:
                    failures += 1
                    print(f'FAIL {backend} {name}: {str(error)[:3000]}')
            print(f'{backend}: {passed} of {len(cases)} {label} proxy cases match pinned pi-mono')
    sys.exit(1 if failures else 0)


main()
