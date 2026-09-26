#!/usr/bin/env python3
"""OpenAI Codex Responses over SSE versus pinned pi-mono (openai-codex-stream.test.ts).

The native runner (packages/ai/test/openai-codex-stream.bend) streams each case
from a loopback server that serves the case's scripted SSE response and records
the request; the pinned upstream stream runs the same script through a stubbed
global fetch (tests/openai_codex_stream_reference.ts). The check compares the
request body, the Codex headers, the event labels and the final message, then
applies the upstream test's own assertions to the native result.
"""
import argparse
import base64
import http.server
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/openai-codex-stream.bend'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/openai-codex-stream')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--only', default='')
parser.add_argument('--pending', action='store_true', help='also run the named tests listed in PENDING')
arguments = parser.parse_args()


def token(account='acc_test'):
    payload = base64.b64encode(json.dumps({'https://api.openai.com/auth': {'chatgpt_account_id': account}}).encode()).decode()
    return f'aaa.{payload}.bbb'


# The upstream fixtures omit output_index, which upstream keys as the JS Map
# key `undefined`; the native decoder requires the field the backend always
# sends, so the fixtures carry output_index 0 (both sides see the same bytes).
INDEXED = ('response.output_item.added', 'response.output_item.done', 'response.content_part.added', 'response.output_text.delta')


def data(event):
    if event.get('type') in INDEXED:
        event = {**event, 'output_index': 0}
    return 'data: ' + json.dumps(event, separators=(',', ':'))


USAGE = {'input_tokens': 5, 'output_tokens': 3, 'total_tokens': 8, 'input_tokens_details': {'cached_tokens': 0}}


def sse(status='completed', include_done=False, end_turn=None, text='Hello', usage=USAGE, service_tier=None):
    terminal = 'response.incomplete' if status == 'incomplete' else 'response.completed'
    response = {'status': status}
    if end_turn is not None:
        response['end_turn'] = end_turn
    if status == 'incomplete':
        response['incomplete_details'] = {'reason': 'max_output_tokens'}
    if service_tier is not None:
        response['service_tier'] = service_tier
    response['usage'] = usage
    events = [
        data({'type': 'response.output_item.added', 'item': {'type': 'message', 'id': 'msg_1', 'role': 'assistant', 'status': 'in_progress', 'content': []}}),
        data({'type': 'response.content_part.added', 'part': {'type': 'output_text', 'text': ''}}),
        data({'type': 'response.output_text.delta', 'delta': text}),
        data({'type': 'response.output_item.done', 'item': {'type': 'message', 'id': 'msg_1', 'role': 'assistant', 'status': 'completed', 'content': [{'type': 'output_text', 'text': text}]}}),
        data({'type': terminal, 'response': response}),
    ]
    if include_done:
        events.append('data: [DONE]')
    return '\n\n'.join(events) + '\n\n'


def step(text='', **extra):
    return dict(status=200, chunks=[[0, text]] if text else [], **extra)


SAY_HELLO = dict(systemPrompt='You are a helpful assistant.', messages=[{'role': 'user', 'content': 'Say hello', 'timestamp': 1}])
PING = {'name': 'ping', 'description': 'Ping', 'parameters': {'type': 'object', 'properties': {'value': {'type': 'string'}}, 'required': ['value']}}

CASES = []

# Named SSE tests that fail against the native Codex path, with the upstream
# behaviour it lacks; --pending runs them.
PENDING = {}


def case(name, script, options=None, check=None, entry='stream', model=None, context=SAY_HELLO, **extra):
    value = dict(name=name, entry=entry, model=model or {'id': 'gpt-5.1-codex', 'name': 'GPT-5.1 Codex'}, options=dict(apiKey=token(), transport='sse', **(options or {})), script=script, **context, **extra)
    CASES.append((value, check))


def text_of(message):
    return next((block['text'] for block in message['content'] if block['type'] == 'text'), None)


def first_request(result):
    return result['requests'][0]


def expect(condition, *detail):
    assert condition, detail


def streams(result):
    headers = first_request(result)['headers']
    expect(headers.get('authorization') == 'Bearer ' + token(), headers)
    expect(headers.get('chatgpt-account-id') == 'acc_test', headers)
    expect(headers.get('openai-beta') == 'responses=experimental', headers)
    expect(headers.get('originator') == 'pi', headers)
    expect(headers.get('accept') == 'text/event-stream', headers)
    expect('x-api-key' not in headers, headers)
    expect(any(e.startswith('text_delta:') for e in result['events']), result['events'])
    expect('done' in result['events'], result['events'])
    expect(text_of(result['message']) == 'Hello', result['message'])


case('streams SSE responses into AssistantMessageEventStream', [step(sse())], check=streams)
case('processes a terminal SSE event without a trailing blank line', [step(sse().rstrip())], check=lambda r: (expect(r['message']['stopReason'] == 'stop', r['message']), expect(text_of(r['message']) == 'Hello', r['message'])))
case('completes after response.completed even when the SSE body stays open', [step(sse(include_done=True, end_turn=False), keepOpen=True)], check=lambda r: (expect(text_of(r['message']) == 'Hello'), expect(r['message']['stopReason'] == 'stop', r['message']), expect(r['message'].get('endTurn') is False, r['message'])))
case('maps response.incomplete to stopReason length even when the SSE body stays open', [step(sse(status='incomplete'), keepOpen=True)], check=lambda r: (expect(text_of(r['message']) == 'Hello'), expect(r['message']['stopReason'] == 'length', r['message'])))
# Upstream uses timeoutMs 10 with an in-process fetch mock; over a real
# loopback connection the request must be sent within the deadline, so both
# sides run with 500ms against a 3s header delay.
case('aborts SSE fetch after the configured HTTP timeout when response headers do not arrive', [step(sse(), headerDelay=3000)], dict(timeoutMs=500), check=lambda r: (expect(len(r['requests']) == 1, r['requests']), expect(r['message']['stopReason'] == 'error', r['message']), expect(r['message'].get('errorMessage') == 'Codex SSE response headers timed out after 500ms', r['message'])))
ONE = '\n\n'.join([data({'type': 'response.output_item.added', 'item': {'type': 'message', 'id': 'msg_1', 'role': 'assistant', 'status': 'in_progress', 'content': []}}), data({'type': 'response.content_part.added', 'part': {'type': 'output_text', 'text': ''}}), data({'type': 'response.output_text.delta', 'delta': 'one'})]) + '\n\n'
TWO = data({'type': 'response.output_text.delta', 'delta': 'two'}) + '\n\n'
REST = '\n\n'.join([data({'type': 'response.output_item.done', 'item': {'type': 'message', 'id': 'msg_1', 'role': 'assistant', 'status': 'completed', 'content': [{'type': 'output_text', 'text': 'onetwo'}]}}), data({'type': 'response.completed', 'response': {'status': 'completed', 'usage': USAGE}})]) + '\n\n'
case('aborts SSE body reads after response headers arrive', [dict(status=200, chunks=[[0, ONE], [300, TWO], [300, REST]])], check=lambda r: (expect(r['message']['stopReason'] == 'aborted', r['message']), expect(r['message'].get('errorMessage') == 'Request was aborted', r['message']), expect('text_delta:one' in r['events'], r['events']), expect('text_delta:two' not in r['events'], r['events'])), abortOnEvent='text_delta:one')


def session(result, key):
    headers = first_request(result)['headers']
    expect(headers.get('session-id') == key, headers)
    expect('session_id' not in headers, headers)
    expect(headers.get('x-client-request-id') == key, headers)
    expect(first_request(result)['body'].get('prompt_cache_key') == key, first_request(result)['body'])


case('sets session-id/x-client-request-id headers and prompt_cache_key when sessionId is provided', [step(sse())], dict(sessionId='test-session-123'), check=lambda r: session(r, 'test-session-123'))
case('omits SSE cache affinity when cacheRetention is none', [step()], dict(cacheRetention='none', sessionId='one-off-summary'), check=lambda r: (expect('session-id' not in first_request(r)['headers']), expect('x-client-request-id' not in first_request(r)['headers']), expect('prompt_cache_key' not in first_request(r)['body'])))
case("clamps prompt_cache_key to OpenAI's 64-character limit", [step()], dict(sessionId='x' * 67), check=lambda r: expect(first_request(r)['body'].get('prompt_cache_key') == 'x' * 64, first_request(r)['body']))
case('clamps Codex session-id header to 64 characters', [step()], dict(sessionId='x' * 67), check=lambda r: (expect(first_request(r)['headers'].get('session-id') == 'x' * 64), expect(first_request(r)['headers'].get('x-client-request-id') == 'x' * 64)))
case('preserves gpt-5.5 xhigh reasoning effort from simple options', [step(sse())], dict(reasoning='xhigh'), entry='simple', model={'id': 'gpt-5.5', 'name': 'GPT-5.5', 'thinkingLevelMap': {'xhigh': 'xhigh'}}, check=lambda r: expect(first_request(r)['body'].get('reasoning') == {'effort': 'xhigh', 'summary': 'auto'}, first_request(r)['body']))
case('forwards required tool choice', [step(sse())], dict(toolChoice='required'), model={'id': 'gpt-5.5', 'name': 'GPT-5.5'}, context=dict(messages=[{'role': 'user', 'content': 'Do not call ping. Respond with text instead.', 'timestamp': 1}], tools=[PING]), check=lambda r: expect(first_request(r)['body'].get('tool_choice') == 'required', first_request(r)['body']))
STRICT_TOOLS = [
    {'name': 'optional', 'description': 'Optional constrained sampling', 'parameters': {'type': 'object', 'properties': {'value': {'type': 'string'}}, 'required': ['value']}, 'constrainedSampling': False},
    {'name': 'strict', 'description': 'Strict constrained sampling', 'parameters': {'additionalProperties': False, 'type': 'object', 'properties': {'value': {'type': 'string'}}, 'required': ['value']}, 'constrainedSampling': {'type': 'json_schema', 'strict': 'prefer'}},
]


def strict_tools(result):
    tools = first_request(result)['body'].get('tools') or []
    expect([(t.get('type'), t.get('name'), t.get('strict')) for t in tools] == [('function', 'optional', None), ('function', 'strict', True)], tools)
    expect(all('strict' in t for t in tools), tools)


case('sets Codex strict mode explicitly and honors constrained sampling', [step(sse())], model={'id': 'gpt-5.5', 'name': 'GPT-5.5'}, context=dict(messages=[{'role': 'user', 'content': 'Use a tool', 'timestamp': 1}], tools=STRICT_TOOLS), check=strict_tools)
for model_id in ['gpt-5.3-codex', 'gpt-5.4', 'gpt-5.5']:
    case(f'clamps {model_id} minimal reasoning effort to low', [step(sse())], dict(reasoning='minimal'), entry='simple', model={'id': model_id, 'name': model_id, 'thinkingLevelMap': {'minimal': 'low'}}, check=lambda r: expect(first_request(r)['body'].get('reasoning') == {'effort': 'low', 'summary': 'auto'}, first_request(r)['body']))
BIG = {'input_tokens': 1000000, 'output_tokens': 1000000, 'total_tokens': 2000000, 'input_tokens_details': {'cached_tokens': 0}}
for model_id, tier, multiplier in [('gpt-5.1-codex', 'flex', 0.5), ('gpt-5.1-codex', 'priority', 2), ('gpt-5.5', 'flex', 0.5), ('gpt-5.5', 'priority', 2.5)]:
    case(f'uses the client-sent {tier} service tier for {model_id} when Codex echoes default', [step(sse(usage=BIG, service_tier='default'))], dict(serviceTier=tier), model={'id': model_id, 'name': 'GPT-5.5' if model_id == 'gpt-5.5' else 'GPT-5.1 Codex', 'cost': {'input': 1, 'output': 2}},
         check=lambda r, m=multiplier: (expect(r['message']['usage']['cost']['input'] == 1 * m, r['message']['usage']), expect(r['message']['usage']['cost']['output'] == 2 * m), expect(r['message']['usage']['cost']['total'] == 3 * m)))
case('does not set session-id/x-client-request-id headers when sessionId is not provided', [step(sse())], check=lambda r: (expect('session-id' not in first_request(r)['headers']), expect('session_id' not in first_request(r)['headers']), expect('x-client-request-id' not in first_request(r)['headers'])))


def json_failure(status, error, headers=None):
    return dict(status=status, headers={'content-type': 'application/json', **(headers or {})}, chunks=[[0, json.dumps({'error': error})]])


for status in (429, 503):
    case(f'fails immediately when a {status} retry delay exceeds the limit', [json_failure(status, {'code': 'temporarily_unavailable', 'message': 'retry later'}, {'retry-after': '2'})], dict(maxRetries=3, maxRetryDelayMs=1000),
         check=lambda r: (expect(r['message']['stopReason'] == 'error', r['message']), expect(r['message'].get('errorMessage') == 'Server requested 2s retry delay (max: 1s)', r['message']), expect(len(r['requests']) == 1, r['requests'])))


# Upstream advances fake timers and inspects setTimeout delays; here the
# retries really wait, and the gaps between the requests the server receives
# must follow the 1s/2s/4s backoff.
def backoff(result):
    expect(text_of(result['message']) == 'Hello', result['message'])
    expect(len(result['requests']) == 4, result['requests'])
    times = [request['at'] for request in result['requests']]
    gaps = [b - a for a, b in zip(times, times[1:])]
    expect(all(want <= gap < want + 1.5 for gap, want in zip(gaps, (1, 2, 4))), gaps)


RATE_LIMITED = json_failure(429, {'code': 'rate_limit_exceeded', 'message': 'rate limited'})
case('uses exponential backoff across repeated SSE retries without retry headers', [RATE_LIMITED, RATE_LIMITED, RATE_LIMITED, step(sse())], dict(maxRetries=3), check=backoff)


# Native cases: parseErrorResponse's messages, which the CLI shows for Codex.
# resets_at is filled in when a response is served (and when the reference
# runs), so the "~90 min" holds however long the native build takes.
RESETS_AT = 4102444800


def fresh(text):
    return text.replace(str(RESETS_AT), str(int(time.time()) + 90 * 60 + 30))
case('native: usage limit reached reports the friendly ChatGPT message', [json_failure(429, {'code': 'usage_limit_reached', 'plan_type': 'PLUS', 'resets_at': RESETS_AT, 'message': 'The usage limit has been reached'})],
     check=lambda r: expect(r['message'].get('errorMessage') == 'You have hit your ChatGPT usage limit (plus plan). Try again in ~90 min.', r['message']))
case('native: a non-retryable status reports the error message', [json_failure(400, {'type': 'invalid_request_error', 'message': 'Unsupported parameter'})], dict(maxRetries=2),
     check=lambda r: (expect(r['message'].get('errorMessage') == 'Unsupported parameter', r['message']), expect(len(r['requests']) == 3, r['requests'])))
case('native: a plain-text error body is the message', [dict(status=502, headers={'content-type': 'text/plain'}, chunks=[[0, 'bad gateway']])],
     check=lambda r: expect(r['message'].get('errorMessage') == 'bad gateway', r['message']))


# Loopback server
# ---------------
class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    scripts = {}
    requests = {}

    def do_POST(self):
        case_id = self.path.split('/')[2]
        length = int(self.headers.get('content-length', '0'))
        raw = self.rfile.read(length)
        body = json.loads(raw.decode()) if raw else None
        seen = Handler.requests.setdefault(case_id, [])
        seen.append({'url': self.path, 'headers': {k.lower(): v for k, v in self.headers.items()}, 'body': body, 'at': time.time()})
        script = Handler.scripts[case_id]
        current = script[min(len(seen) - 1, len(script) - 1)]
        if current.get('headerDelay'):
            time.sleep(current['headerDelay'] / 1000)
        try:
            self.send_response(current.get('status', 200))
            for key, value in (current.get('headers') or {'content-type': 'text/event-stream'}).items():
                self.send_header(key, value)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            for delay, text in current.get('chunks', []):
                if delay:
                    time.sleep(delay / 1000)
                encoded = fresh(text).encode()
                self.wfile.write(f'{len(encoded):x}\r\n'.encode() + encoded + b'\r\n')
                self.wfile.flush()
            if current.get('keepOpen'):
                deadline = time.time() + 5
                while time.time() < deadline:
                    time.sleep(0.05)
                    self.wfile.write(b'')
            self.wfile.write(b'0\r\n\r\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.close_connection = True

    def log_message(self, *_):
        pass


def encode(value):
    return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=False, separators=(',', ':')))


def reference(cases):
    result = subprocess.run(['bun', 'tests/openai_codex_stream_reference.ts'], cwd=ROOT, input=fresh(json.dumps({'cases': cases})), capture_output=True, text=True, env={**os.environ, 'PI_MONO_ROOT': str(UPSTREAM)}, timeout=600)
    assert result.returncode == 0, result.stderr[-3000:]
    return json.loads(result.stdout)


IGNORED_HEADERS = {'host', 'content-length', 'content-encoding', 'connection', 'user-agent', 'accept-encoding', 'transfer-encoding'}


def comparable(result):
    message = dict(result['message'])
    message.pop('timestamp', None)
    requests = [{'headers': {k: v for k, v in request['headers'].items() if k not in IGNORED_HEADERS}, 'body': request['body']} for request in result['requests']]
    return {'requests': requests, 'events': result['events'], 'message': message}


def main():
    selected = [(value, check) for value, check in CASES if arguments.only in value['name'] and (arguments.pending or value['name'] not in PENDING)]
    for name, reason in PENDING.items():
        print(f'PENDING {name}: {reason}')
    expected = reference([value for value, _ in selected])
    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    failures = 0
    try:
        for backend in arguments.backends:
            command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
            passed = 0
            for index, ((value, check), want) in enumerate(zip(selected, expected)):
                case_id = f'{backend}-{index}'
                Handler.scripts[case_id] = value['script']
                Handler.requests[case_id] = []
                base = f'http://127.0.0.1:{server.server_port}/c/{case_id}'
                started = time.time()
                run = subprocess.run(command + [base, encode(value)], cwd=ROOT, capture_output=True, text=True, timeout=120)
                elapsed = time.time() - started
                try:
                    assert run.returncode == 0, (run.stdout[-1500:], run.stderr[-1500:])
                    events = [line[2:] for line in run.stdout.splitlines() if line.startswith('E ')]
                    message = json.loads(''.join(chr(int(p)) for p in next(line[2:] for line in run.stdout.splitlines() if line.startswith('R ')).split(',')))
                    got = {'requests': Handler.requests[case_id], 'events': events, 'message': message}
                    assert 'thrown' not in want, want
                    mine, theirs = comparable(got), comparable(want)
                    for part in ('requests', 'events', 'message'):
                        assert mine[part] == theirs[part], (f'{part} differ from upstream', mine[part] if part != 'message' else {k: v for k, v in mine[part].items() if theirs[part].get(k) != v}, theirs[part] if part != 'message' else {k: v for k, v in theirs[part].items() if mine[part].get(k) != v})
                    if check:
                        check(got)
                    if value['script'][0].get('keepOpen'):
                        assert elapsed < 4, f'waited {elapsed:.1f}s for the open body'
                    passed += 1
                    print(f'PASS {backend} {value["name"]}')
                except AssertionError as error:
                    failures += 1
                    print(f'FAIL {backend} {value["name"]}: {str(error)[:2500]}')
            print(f'{backend}: {passed} of {len(selected)} named Codex SSE tests match pinned pi-mono')
    finally:
        server.shutdown()
    sys.exit(1 if failures else 0)


main()
