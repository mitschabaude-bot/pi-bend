"""Chat Completions stream side versus pinned upstream, with the upstream suites' named cases.

Both the native provider (tests/openai-completions-stream.bend) and pinned
pi-mono (tests/openai_completions_stream_reference.ts) stream from the same
scripted local HTTP server. Every event (without upstream's aliased
`partial`), the final message (timestamp masked) and every request the server
received must be equal; each named case then applies the upstream test's own
assertions to the native result. convertMessages cases of the thinking-as-text
suite run through the request harness (tests/openai-completions-request.bend).
"""
from upstream_pin import UPSTREAM
import argparse
import copy
import http.server
import itertools
import json
import os
import random
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'tests/openai-completions-stream.bend'
REQUEST_ENTRY = 'tests/openai-completions-request.bend'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/openai-completions-stream')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--only', help='run cases whose suite/name contains this text')
arguments = parser.parse_args()

revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=UPSTREAM, text=True).strip()
assert revision.startswith('f07218c4d'), revision


# Scripted server
# ---------------

class Handler(http.server.BaseHTTPRequestHandler):
    scripts = {}
    counters = {}
    received = {}

    def do_POST(self):
        parts = self.path.split('/')
        case_id = parts[2] if len(parts) > 2 and parts[1] == 'c' else ''
        body = self.rfile.read(int(self.headers.get('content-length') or 0)).decode()
        headers = {key.lower(): value for key, value in self.headers.items()}
        Handler.received.setdefault(case_id, []).append(dict(path='/' + '/'.join(parts[3:]), headers=headers, body=body))
        index = Handler.counters.get(case_id, 0)
        Handler.counters[case_id] = index + 1
        script = Handler.scripts.get(case_id, [])
        response = script[min(index, len(script) - 1)] if script else dict(status=500, body='{}')
        self.send_response(response.get('status', 200))
        for key, value in response.get('headers', {}).items():
            self.send_header(key, value)
        parts = [part.encode() for part in response.get('parts', [response.get('body', '')])]
        self.send_header('Content-Type', response.get('type', 'text/event-stream'))
        self.send_header('Content-Length', str(sum(len(part) for part in parts)))
        self.end_headers()
        try:
            for index, part in enumerate(parts):
                if index:
                    time.sleep(response.get('stall', 0))
                self.wfile.write(part)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


def sse(chunks, done=True):
    text = ''.join('data: ' + (chunk if isinstance(chunk, str) else json.dumps(chunk)) + '\n\n' for chunk in chunks)
    return dict(status=200, body=text + ('data: [DONE]\n\n' if done else ''))


def failure(status, message, headers=None):
    return dict(status=status, headers=headers or {}, type='application/json', body=json.dumps({'error': {'message': message}}))


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
PORT = server.server_port


# Fixtures
# --------

NOW = 1700000000000
ZERO_USAGE = dict(input=0, output=0, cacheRead=0, cacheWrite=0, totalTokens=0, cost=dict(input=0, output=0, cacheRead=0, cacheWrite=0, total=0))
COST = dict(input=0, output=0, cacheRead=0, cacheWrite=0)
CATALOG = {}
USAGE = dict(prompt_tokens=1, completion_tokens=1, prompt_tokens_details=dict(cached_tokens=0), completion_tokens_details=dict(reasoning_tokens=0))


def catalog(provider, model_id):
    key = (provider, model_id)
    if key not in CATALOG:
        CATALOG[key] = json.loads(subprocess.check_output(['bun', 'tests/openai_completions_request_reference.ts'], input=json.dumps({'models': [list(key)]}), text=True, cwd=ROOT))[0]
    return copy.deepcopy(CATALOG[key])


def model_of(fields):
    fields = copy.deepcopy(fields)
    provider = fields.pop('provider')
    fields.pop('baseUrl', None)
    fields.pop('api', None)
    return dict(provider=provider, model=fields)


def gpt4o_mini(**overrides):
    fields = catalog('openai', 'gpt-4o-mini')
    fields.pop('compat', None)
    fields.update(overrides)
    return model_of(fields)


def test_model(**overrides):
    return model_of(dict(dict(id='test-model', name='Test Model', provider='openai', reasoning=False, input=['text'], cost=COST, contextWindow=128000, maxTokens=4096), **overrides))


def user(content, timestamp=NOW):
    return dict(role='user', content=content, timestamp=timestamp)


def tool(name, description, properties, **extra):
    return dict(name=name, description=description, parameters=dict(type='object', properties=properties, required=list(properties)), **extra)


def chunk(delta, finish=None, **extra):
    return dict(dict(id='chatcmpl-test', choices=[dict(index=0, delta=delta, finish_reason=finish)]), **extra)


CASES = []
SERIAL = itertools.count()


def fixture(entry, model, messages, script, options=None, **extra):
    case_id = str(next(SERIAL))
    value = dict(entry=entry, messages=messages, options=dict(options or {}), baseUrl=f'http://127.0.0.1:{PORT}/c/{case_id}', id=case_id, script=script)
    value.update(model)
    value.update(extra)
    return value


def simple(model, messages, script, options=None, **extra):
    return fixture('simple', model, messages, script, dict(dict(apiKey='test'), **(options or {})), **extra)


def streamed(model, messages, script, options=None, **extra):
    return fixture('stream', model, messages, script, dict(dict(apiKey='test'), **(options or {})), **extra)


def test(suite, name, fixtures, check, follow=None):
    CASES.append(dict(suite=suite, name=name, fixtures=fixtures if isinstance(fixtures, list) else [fixtures], check=check, follow=follow))


def equal(actual, expected):
    assert actual == expected, (actual, expected)


def message(result):
    return result['message']


def blocks(result):
    return message(result)['content']


# openai-completions-raw-stop-reason.test.ts
# ------------------------------------------

S = 'openai-completions-raw-stop-reason'


def raw_stop(stop, raw, error):
    def check(results):
        value = message(results[0])
        equal(value['stopReason'], stop)
        equal(value.get('rawStopReason'), raw)
        equal(value.get('errorMessage'), error)
    return check


test(S, 'preserves raw finish reasons for successful stops', streamed(test_model(), [user('hello')], [sse([dict(id='chatcmpl-1', choices=[dict(index=0, delta={}, finish_reason='stop')])])]), raw_stop('stop', 'stop', None))
test(S, 'preserves raw finish reasons for provider error stops', streamed(test_model(), [user('hello')], [sse([dict(id='chatcmpl-2', choices=[dict(index=0, delta={}, finish_reason='content_filter')])])]), raw_stop('error', 'content_filter', 'Provider finish_reason: content_filter'))

# openai-completions-response-model.test.ts
# -----------------------------------------

S = 'openai-completions-response-model'
AUTO = model_of(dict(id='openrouter/auto', name='OpenRouter Auto', provider='openrouter', reasoning=False, input=['text'], cost=COST, contextWindow=200000, maxTokens=8192))
ROUTED_USAGE = dict(prompt_tokens=10, completion_tokens=5, prompt_tokens_details=dict(cached_tokens=0), completion_tokens_details=dict(reasoning_tokens=0))


def routed(results):
    value = message(results[0])
    equal(value['model'], 'openrouter/auto')
    equal(value.get('responseModel'), 'anthropic/claude-opus-4.8')
    equal(value['provider'], 'openrouter')
    equal(value['stopReason'], 'stop')


test(S, 'surfaces routed chunk.model on responseModel without changing model', simple(AUTO, [user('hi')], [sse([dict(id='chatcmpl-1', model='anthropic/claude-opus-4.8', choices=[dict(index=0, delta=dict(content='hi'))]), dict(id='chatcmpl-1', model='anthropic/claude-opus-4.8', choices=[dict(index=0, delta={}, finish_reason='stop')], usage=ROUTED_USAGE)])]), routed)


def unrouted(results):
    value = message(results[0])
    equal(value['model'], 'openrouter/auto')
    assert 'responseModel' not in value, value


test(S, 'leaves responseModel undefined when chunks echo the requested id', simple(AUTO, [user('hi')], [sse([dict(id='chatcmpl-2', model='openrouter/auto', choices=[dict(index=0, delta=dict(content='hi'))]), dict(id='chatcmpl-2', model='openrouter/auto', choices=[dict(index=0, delta={}, finish_reason='stop')], usage=USAGE)])]), unrouted)
test(S, 'ignores empty or missing chunk.model', simple(AUTO, [user('hi')], [sse([dict(id='chatcmpl-3', choices=[dict(index=0, delta=dict(content='hi'))]), dict(id='chatcmpl-3', model='', choices=[dict(index=0, delta=dict(content='!'))]), dict(id='chatcmpl-3', choices=[dict(index=0, delta={}, finish_reason='stop')], usage=dict(USAGE, completion_tokens=2))])]), unrouted)

# openai-completions-reasoning-details.test.ts
# --------------------------------------------

S = 'openai-completions-reasoning-details'
DETAIL = dict(type='reasoning.encrypted', id='call_1', data='encrypted-signature')
SIGNED_TEXT = dict(type='reasoning.text', text='I should call the read tool.', signature='sha256:signed-text', id='reasoning-text-1', format='anthropic-claude-v1', index=0)
SUMMARY = dict(type='reasoning.summary', summary='Decided to inspect the requested file.', id='reasoning-summary-1', format='anthropic-claude-v1', index=1)
READ = tool('read', 'Read a file', dict(path=dict(type='string')))
GEMINI = model_of(dict(id='google/gemini-test', name='Gemini Test', provider='openrouter', reasoning=True, input=['text'], cost=COST, contextWindow=100000, maxTokens=4096))


def gemini_chunk(delta, finish=None):
    return dict(id='chatcmpl-test', model='google/gemini-test', choices=[dict(index=0, delta=delta, finish_reason=finish)])


TOOL_CALL_CHUNK = gemini_chunk(dict(tool_calls=[dict(index=0, id='call_1', type='function', function=dict(name='read', arguments='{"path":"README.md"}'))]))
SECOND_TURN = [sse([gemini_chunk(dict(content='ok')), gemini_chunk({}, 'stop')])]


def details_turn(first_chunks):
    return streamed(GEMINI, [], [sse(first_chunks)], tools=[READ])


def replayed_details(results):
    body = json.loads(results[1]['requests'][0]['body'])
    return next(m for m in body['messages'] if m['role'] == 'assistant')


def with_replay(transform=None):
    def follow(first):
        replay = copy.deepcopy(message(first))
        if transform:
            transform(replay)
        return streamed(GEMINI, [replay], SECOND_TURN, tools=[READ])
    return follow


def preserved(results):
    content = blocks(results[0])
    equal(next(b for b in content if b['type'] == 'thinking'), dict(type='thinking', thinking='', thinkingSignature=json.dumps([DETAIL], separators=(',', ':'))))
    equal(next(b for b in content if b['type'] == 'toolCall'), dict(type='toolCall', id='call_1', name='read', arguments=dict(path='README.md')))
    equal(replayed_details(results).get('reasoning_details'), [DETAIL])


test(S, 'preserves reasoning_details in the thinking signature', details_turn([gemini_chunk(dict(reasoning_details=[DETAIL])), TOOL_CALL_CHUNK, gemini_chunk({}, 'tool_calls')]), preserved, follow=with_replay())


def legacy(replay):
    replay['content'] = [b for b in replay['content'] if b['type'] != 'thinking']
    next(b for b in replay['content'] if b['type'] == 'toolCall')['thoughtSignature'] = json.dumps(DETAIL)


test(S, 'falls back to encrypted tool-call signatures for older stored assistant messages', details_turn([gemini_chunk(dict(reasoning_details=[DETAIL])), TOOL_CALL_CHUNK, gemini_chunk({}, 'tool_calls')]), lambda r: equal(replayed_details(r).get('reasoning_details'), [DETAIL]), follow=with_replay(legacy))


def in_sequence(results):
    expected = [SIGNED_TEXT, DETAIL, SUMMARY]
    equal(next(b for b in blocks(results[0]) if b['type'] == 'thinking'), dict(type='thinking', thinking=SIGNED_TEXT['text'], thinkingSignature=json.dumps(expected, separators=(',', ':'))))
    payload = replayed_details(results)
    equal(payload.get('reasoning_details'), expected)
    assert 'reasoning' not in payload, payload


test(S, 'preserves signed text and summary reasoning_details in their original sequence', details_turn([gemini_chunk(dict(reasoning=SIGNED_TEXT['text'], reasoning_details=[SIGNED_TEXT])), gemini_chunk(dict(reasoning_details=[DETAIL, SUMMARY])), TOOL_CALL_CHUNK, gemini_chunk({}, 'tool_calls')]), in_sequence, follow=with_replay())
TEXT_DELTA = {'type': 'reasoning.text', 'text': 'The', 'index': 0}
TEXT_SIGNED = {'type': 'reasoning.text', 'text': ' user wants the time.', 'signature': 'sha256:text-signature', 'format': 'openai-responses-v1', 'index': 0}
SUMMARY_DELTA = {'type': 'reasoning.summary', 'summary': 'Looked', 'index': 0}
SUMMARY_FORMAT = {'type': 'reasoning.summary', 'summary': ' up time.', 'format': 'openai-responses-v1', 'index': 0}
LATER_SUMMARY = {'type': 'reasoning.summary', 'summary': 'After encrypted block.', 'format': 'openai-responses-v1', 'index': 0}
MERGED = [{'type': 'reasoning.text', 'text': 'The user wants the time.', 'index': 0, 'signature': 'sha256:text-signature', 'format': 'openai-responses-v1'}, {'type': 'reasoning.summary', 'summary': 'Looked up time.', 'index': 0, 'format': 'openai-responses-v1'}, DETAIL, LATER_SUMMARY]


def merged(results):
    equal(next(b for b in blocks(results[0]) if b['type'] == 'thinking'), dict(type='thinking', thinking='', thinkingSignature=json.dumps(MERGED, separators=(',', ':'))))
    equal(replayed_details(results).get('reasoning_details'), MERGED)


test(S, 'merges consecutive text and summary reasoning_details deltas before replay', details_turn([gemini_chunk(dict(reasoning_details=[d])) for d in (TEXT_DELTA, TEXT_SIGNED, SUMMARY_DELTA, SUMMARY_FORMAT, DETAIL, LATER_SUMMARY)] + [TOOL_CALL_CHUNK, gemini_chunk({}, 'tool_calls')]), merged, follow=with_replay())

# openai-completions-thinking-as-text.test.ts
# -------------------------------------------

S = 'openai-completions-thinking-as-text'
AS_TEXT = dict(supportsStore=True, supportsDeveloperRole=True, supportsReasoningEffort=True, supportsUsageInStreaming=True, supportsFinishReason=True, maxTokensField='max_completion_tokens', requiresToolResultName=False, requiresAssistantAfterToolResult=False, requiresThinkingAsText=True, requiresReasoningContentOnAssistantMessages=False, thinkingFormat='openai', openRouterRouting={}, vercelGatewayRouting={}, chatTemplateKwargs={}, chatTemplateArgs={}, zaiToolStream=False, supportsThinkingTokenBudget=False, supportsStrictMode=True, supportsOpenAIGrammarTools=False, supportsMidConvoSystemMessages=False, supportsMidConvoToolAdditions=False, sendSessionAffinityHeaders=False, sessionAffinityFormat='openai', supportsLongCacheRetention=True)
REPRO = model_of(dict(id='repro-model', name='Repro Model', provider='repro-provider', reasoning=True, input=['text'], cost=COST, contextWindow=128000, maxTokens=4096, compat=AS_TEXT))


def repro_context(content):
    return [user('hello', 1), dict(role='assistant', content=content, api='openai-completions', provider='repro-provider', model='repro-model', usage=ZERO_USAGE, stopReason='stop', timestamp=2), user('continue', 3)]


BOTH = [dict(type='thinking', thinking='internal reasoning'), dict(type='text', text='visible answer')]
AS_PARTS = [{'type': 'text', 'text': 'internal reasoning'}, {'type': 'text', 'text': 'visible answer'}]


def converted(content, expected):
    fixture_value = dict(REPRO, entry='convert', messages=repro_context(content), compat=AS_TEXT, baseUrl='http://127.0.0.1:1', id='convert')
    return dict(fixture_value, convert=True)


def second_message(expected):
    def check(results):
        equal(json.loads(results[0]['messages'])[1], expected)
    return check


test(S, 'serializes same-model thinking-plus-text replay as assistant text parts', converted(BOTH, None), second_message({'role': 'assistant', 'content': AS_PARTS}))
test(S, 'serializes same-model thinking-only replay as assistant text parts', converted([dict(type='thinking', thinking='internal reasoning')], None), second_message({'role': 'assistant', 'content': [{'type': 'text', 'text': 'internal reasoning'}]}))


def reached(results):
    requests = results[0]['requests']
    equal(len(requests), 1)
    equal(json.loads(requests[0]['body'])['messages'][1], {'role': 'assistant', 'content': AS_PARTS})
    equal(results[0]['events'][-1]['type'], 'done')


test(S, 'reaches the endpoint when replay contains both thinking and text', streamed(REPRO, repro_context(BOTH), [sse([dict(id='chatcmpl-repro', object='chat.completion.chunk', created=0, model='repro-model', choices=[dict(index=0, delta=dict(role='assistant', content='ok'), finish_reason=None)]), dict(id='chatcmpl-repro', object='chat.completion.chunk', created=0, model='repro-model', choices=[dict(index=0, delta={}, finish_reason='stop')], usage=dict(prompt_tokens=1, completion_tokens=1))])], dict(apiKey='test-key')), reached)

# openai-completions-retry.test.ts
# --------------------------------

S = 'openai-completions-retry'
RETRY_MODEL = model_of(dict(id='test-model', name='Test Model', provider='opencode-go', reasoning=False, input=['text'], cost=COST, contextWindow=1000, maxTokens=100))
RETRY_CONTEXT = dict(systemPrompt='', tools=[])
OK_STREAM = sse([dict(id='chatcmpl-test', choices=[dict(index=0, delta=dict(content='ok'))]), dict(id='chatcmpl-test', choices=[dict(index=0, delta={}, finish_reason='stop')])])


def sdk_retries_disabled(count):
    def check(results):
        requests = results[0]['requests']
        equal(len(requests), count)
        for request in requests:
            equal(request['headers'].get('x-stainless-retry-count'), '0')
    return check


test(S, 'disables SDK retries by default', streamed(RETRY_MODEL, [user([dict(type='text', text='hi')], 0)], [OK_STREAM], **RETRY_CONTEXT), sdk_retries_disabled(1))


def honored(results):
    sdk_retries_disabled(3)(results)
    equal(message(results[0])['stopReason'], 'stop')


test(S, 'honors provider retries while keeping SDK retries disabled', streamed(RETRY_MODEL, [user([dict(type='text', text='hi')], 0)], [failure(429, 'rate limited', {'retry-after-ms': '100'}), failure(500, 'server error', {'retry-after-ms': '100'}), OK_STREAM], dict(maxRetries=2, maxRetryDelayMs=100), **RETRY_CONTEXT), honored)


def delay_limit(results):
    value = message(results[0])
    equal(value['stopReason'], 'error')
    assert 'Server requested 277403s retry delay (max: 1s)' in value['errorMessage'], value
    assert 'rate limited' in value['errorMessage'], value
    sdk_retries_disabled(1)(results)


test(S, 'fails immediately when a provider-requested retry delay exceeds the limit', streamed(RETRY_MODEL, [user([dict(type='text', text='hi')], 0)], [failure(429, 'rate limited', {'retry-after': '277403'})], dict(maxRetries=2, maxRetryDelayMs=1000), **RETRY_CONTEXT), delay_limit)

# openai-completions-tool-choice.test.ts (stream side)
# ----------------------------------------------------

S = 'openai-completions-tool-choice'
GLM = catalog('zai', 'glm-5.2')
GLM['baseUrl'] = 'unused'


def stop_error(results):
    value = message(results[0])
    equal(value['stopReason'], 'error')
    equal(value['errorMessage'], 'Provider finish_reason: network_error')


test(S, 'maps non-standard provider finish_reason values to stopReason error', simple(model_of(GLM), [user('Hi')], [sse([dict(choices=[dict(delta=dict(content='partial'), finish_reason=None)]), dict(choices=[dict(delta={}, finish_reason='network_error')], usage=USAGE)])]), stop_error)


def null_chunks(results):
    value = message(results[0])
    equal(value['stopReason'], 'stop')
    assert 'errorMessage' not in value, value
    equal(value['responseId'], 'chatcmpl-test')
    equal(value['usage']['totalTokens'], 4)
    equal(value['content'], [dict(type='text', text='OK')])


test(S, 'ignores null stream chunks from openai-compatible providers', simple(gpt4o_mini(), [user('Reply with exactly OK')], [sse(['null', dict(id='chatcmpl-test', choices=[dict(delta=dict(content='OK'), finish_reason=None)]), dict(id='chatcmpl-test', choices=[dict(delta={}, finish_reason='stop')], usage=dict(USAGE, prompt_tokens=3))])]), null_chunks)


def truncated(results):
    value = message(results[0])
    equal(value['stopReason'], 'error')
    equal(value['errorMessage'], 'Stream ended without finish_reason')


test(S, 'errors when a stream ends after only null finish_reason chunks', simple(gpt4o_mini(), [user('Reply with a longer sentence')], [sse([dict(id='chatcmpl-truncated', choices=[dict(delta=dict(content='partial answer'), finish_reason=None)])] * 2)]), truncated)


def accepted(results):
    value = message(results[0])
    equal(value['stopReason'], 'stop')
    assert 'errorMessage' not in value, value
    equal(value['content'], [dict(type='text', text='complete answer')])


test(S, 'accepts streams without finish_reason when compat disables it', simple(gpt4o_mini(compat=dict(supportsFinishReason=False)), [user('Reply with a complete answer')], [sse([dict(id='chatcmpl-no-finish-reason', choices=[dict(delta=dict(content='complete answer'), finish_reason=None)])])]), accepted)
test(S, 'ignores empty custom objects on function tool call deltas', simple(gpt4o_mini(), [user('Read README.md')], [sse([dict(id='chatcmpl-empty-custom', choices=[dict(delta=dict(tool_calls=[dict(index=0, id='call_1', type='function', function=dict(name='read', arguments='{"path":"README.md"}'), custom={})]), finish_reason='tool_calls')])])], tools=[READ]), lambda r: equal(blocks(r[0]), [dict(type='toolCall', id='call_1', name='read', arguments=dict(path='README.md'))]))


def kimi(results):
    value = message(results[0])
    equal(value['stopReason'], 'toolUse')
    equal([e['contentIndex'] for e in results[0]['events'] if e['type'] in ('toolcall_start', 'toolcall_delta', 'toolcall_end')], [0, 0, 0, 0, 0])
    equal(len(value['content']), 1)
    call = value['content'][0]
    equal(call, dict(type='toolCall', id='functions.read:0', name='read', arguments=dict(path='README.md')))


def kimi_chunk(call_id, name, args, finish=None, **extra):
    return dict(dict(id='chatcmpl-kimi-bad-stream', choices=[dict(delta=dict(tool_calls=[dict(index=0, id=call_id, type='function', function=dict(name=name, arguments=args))]), finish_reason=finish)]), **extra)


test(S, 'coalesces tool call deltas by stable index when provider mutates ids mid-stream', simple(gpt4o_mini(), [user('Read README.md')], [sse([kimi_chunk('functions.read:0', 'read', ''), kimi_chunk('chatcmpl-tool-a', None, '{"path":"README'), kimi_chunk('chatcmpl-tool-b', None, '.md"}', 'tool_calls', usage=dict(USAGE, prompt_tokens=10, completion_tokens=5))])], tools=[READ]), kimi)
MIXED_TOOLS = [READ, tool('grep', 'Search a file', dict(pattern=dict(type='string'), path=dict(type='string'))), tool('list', 'List a directory', dict(path=dict(type='string'))), tool('write', 'Write a file', dict(path=dict(type='string'), content=dict(type='string')))]


def fn(name=None, args=None):
    value = {}
    if name is not None:
        value['name'] = name
    if args is not None:
        value['arguments'] = args
    return value


MIXED = [
    dict(id='chatcmpl-mixed-deltas', choices=[dict(delta=dict(content='answer 1', reasoning_content='think 1', tool_calls=[dict(index=0, id='tc_read_initial', type='function', function=fn('read', '{"path":"README')), dict(index=1, id='tc_grep_initial', type='function', function=fn('grep', '{"pattern":"TODO')), dict(id='tc_list_no_index', type='function', function=fn('list', '{"path":"packages')), dict(id='tc_write_no_index', type='function', function=fn('write', '{"path":"out'))]), finish_reason=None)]),
    dict(id='chatcmpl-mixed-deltas', choices=[dict(delta=dict(content=' answer 2', tool_calls=[dict(index=1, id='tc_grep_changed', type='function', function=fn(None, '","path":"src')), dict(id='tc_write_no_index', type='function', function=fn(None, '.txt","content":"ok"}')), dict(id='tc_list_no_index', type='function', function=fn(None, '/ai"}'))]), finish_reason=None)]),
    dict(id='chatcmpl-mixed-deltas', choices=[dict(delta=dict(content='\n', reasoning_content=' think 2', tool_calls=[dict(index=0, id='tc_read_changed', type='function', function=fn(None, '.md"}')), dict(index=1, type='function', function=fn(None, '"}'))]), finish_reason='tool_calls')], usage=dict(prompt_tokens=10, completion_tokens=8, prompt_tokens_details=dict(cached_tokens=0), completion_tokens_details=dict(reasoning_tokens=2))),
]


def mixed(results):
    value = message(results[0])
    types = [e['type'] for e in results[0]['events']]
    equal(value['stopReason'], 'toolUse')
    for kind, count in dict(text_start=1, text_delta=3, text_end=1, thinking_start=1, thinking_delta=2, thinking_end=1, toolcall_start=4, toolcall_delta=9, toolcall_end=4).items():
        equal(types.count(kind), count)
    by_index = {}
    for event in results[0]['events']:
        if event['type'].startswith('toolcall_'):
            by_index.setdefault(event['contentIndex'], []).append(event['type'])
    equal(by_index[2], ['toolcall_start', 'toolcall_delta', 'toolcall_delta', 'toolcall_end'])
    equal(by_index[3], ['toolcall_start', 'toolcall_delta', 'toolcall_delta', 'toolcall_delta', 'toolcall_end'])
    equal(by_index[4], ['toolcall_start', 'toolcall_delta', 'toolcall_delta', 'toolcall_end'])
    equal(by_index[5], ['toolcall_start', 'toolcall_delta', 'toolcall_delta', 'toolcall_end'])
    content = value['content']
    equal(len(content), 6)
    equal(content[0], dict(type='text', text='answer 1 answer 2\n'))
    equal(content[1], dict(type='thinking', thinking='think 1 think 2', thinkingSignature='reasoning_content'))
    equal(content[2], dict(type='toolCall', id='tc_read_initial', name='read', arguments=dict(path='README.md')))
    equal(content[3], dict(type='toolCall', id='tc_grep_initial', name='grep', arguments=dict(pattern='TODO', path='src')))
    equal(content[4], dict(type='toolCall', id='tc_list_no_index', name='list', arguments=dict(path='packages/ai')))
    equal(content[5], dict(type='toolCall', id='tc_write_no_index', name='write', arguments=dict(path='out.txt', content='ok')))


test(S, 'accumulates mixed content, reasoning, and parallel tool call deltas independently', simple(gpt4o_mini(), [user('Think, answer, and use tools.')], [sse(MIXED)], tools=MIXED_TOOLS), mixed)
OPENCODE_GO = catalog('opencode-go', 'kimi-k2.6')
OPENCODE_GO.pop('compat', None)


def signature(expected):
    return lambda r: equal(blocks(r[0]), [dict(type='thinking', thinking='think', thinkingSignature=expected)])


test(S, 'normalizes OpenCode Go reasoning deltas to reasoning_content for replay', simple(model_of(OPENCODE_GO), [user('Use reasoning.')], [sse([dict(id='chatcmpl-opencode-go-reasoning', choices=[dict(delta=dict(reasoning='think'), finish_reason='stop')])])]), signature('reasoning_content'))
test(S, 'keeps non-OpenCode Go reasoning deltas on the original reasoning field', simple(gpt4o_mini(), [user('Use reasoning.')], [sse([dict(id='chatcmpl-reasoning', choices=[dict(delta=dict(reasoning='think'), finish_reason='stop')])])]), signature('reasoning'))


def usage_is(**expected):
    def check(results):
        usage = message(results[0])['usage']
        for key, value in expected.items():
            equal(usage[key], value)
    return check


test(S, 'does not double-count reasoning tokens in completion usage', simple(gpt4o_mini(), [user('Use reasoning.')], [sse([dict(id='chatcmpl-reasoning-usage', choices=[dict(delta={}, finish_reason='stop')], usage=dict(prompt_tokens=10, completion_tokens=33, prompt_tokens_details=dict(cached_tokens=0), completion_tokens_details=dict(reasoning_tokens=21)))])]), usage_is(input=10, output=33, totalTokens=43))
CACHE_USAGE = dict(prompt_tokens=100, completion_tokens=5, prompt_tokens_details=dict(cached_tokens=50, cache_write_tokens=30), completion_tokens_details=dict(reasoning_tokens=0))
test(S, 'preserves prompt_tokens_details cache read/write fields from chunk usage', simple(gpt4o_mini(), [user('Reply with exactly OK')], [sse([dict(id='chatcmpl-cache-write', choices=[dict(delta=dict(content='OK'), finish_reason=None)]), dict(id='chatcmpl-cache-write', choices=[dict(delta={}, finish_reason='stop')], usage=CACHE_USAGE)])]), usage_is(input=20, cacheRead=50, cacheWrite=30, totalTokens=105))
test(S, 'preserves prompt_tokens_details cache read/write fields from choice usage fallback', simple(gpt4o_mini(), [user('Reply with exactly OK')], [sse([dict(id='chatcmpl-cache-write-choice', choices=[dict(delta=dict(content='OK'), finish_reason=None)]), dict(id='chatcmpl-cache-write-choice', choices=[dict(delta={}, finish_reason='stop', usage=CACHE_USAGE)])])]), usage_is(input=20, cacheRead=50, cacheWrite=30, totalTokens=105))

# Follow-up differential cases
# ----------------------------

S = 'native: github-copilot dynamic headers'
COPILOT = model_of(dict(id='gpt-4.1', name='GPT-4.1', provider='github-copilot', reasoning=False, input=['text', 'image'], cost=COST, contextWindow=128000, maxTokens=4096, headers={'Editor-Version': 'vscode/1.107.0'}))
IMAGE = dict(type='image', data='ZmFrZQ==', mimeType='image/png')
OK_ONLY = [sse([chunk(dict(content='ok')), chunk({}, 'stop')])]
COPILOT_TOOL_TURN = [user('look'), dict(role='assistant', content=[dict(type='toolCall', id='c1', name='read', arguments=dict(path='a.png'))], api='openai-completions', provider='github-copilot', model='gpt-4.1', usage=ZERO_USAGE, stopReason='toolUse', timestamp=NOW), dict(role='toolResult', toolCallId='c1', toolName='read', content=[dict(type='text', text='image'), IMAGE], isError=False, timestamp=NOW)]


def copilot_headers(initiator, vision):
    def check(results):
        headers = results[0]['requests'][0]['headers']
        equal(headers.get('x-initiator'), initiator)
        equal(headers.get('openai-intent'), 'conversation-edits')
        equal(headers.get('copilot-vision-request'), vision)
        equal(headers.get('editor-version'), 'vscode/1.107.0')
    return check


test(S, 'user-initiated text request', simple(COPILOT, [user('hi')], OK_ONLY), copilot_headers('user', None))
test(S, 'agent-initiated request after an image tool result', simple(COPILOT, COPILOT_TOOL_TURN, OK_ONLY, tools=[READ]), copilot_headers('agent', 'true'))
test(S, 'user image blocks request vision', simple(COPILOT, [user([dict(type='text', text='see'), IMAGE])], OK_ONLY), copilot_headers('user', 'true'))
test(S, 'option headers override the dynamic headers', simple(COPILOT, [user('hi')], OK_ONLY, dict(headers={'X-Initiator': 'agent', 'Openai-Intent': 'custom'})), lambda r: (equal(r[0]['requests'][0]['headers'].get('x-initiator'), 'agent'), equal(r[0]['requests'][0]['headers'].get('openai-intent'), 'custom')))

S = 'native: OpenRouter raw metadata as String(raw)'
RAW_VALUES = [('string', 'raw upstream text'), ('number', 42), ('fraction', 1.5), ('true', True), ('false', False), ('zero', 0), ('empty', ''), ('null', None), ('array', [1, 'a', [2, None], True]), ('object', {'x': 1}), ('empty-array', []), ('contained', 'Provider returned error')]


# upstream appends `\n${raw}` for a truthy raw unless the message already
# contains String(raw).
def raw_suffix(expected):
    def check(results):
        message_text = message(results[0])['errorMessage']
        if expected is None:
            assert '\n' not in message_text, message_text
        else:
            head, _, tail = message_text.partition('\n')
            assert (tail == expected and expected not in head) or (not tail and expected in head), (message_text, expected)
    return check


JS_STRING = dict(string='raw upstream text', number='42', fraction='1.5', true='true', array='1,a,2,,true', object='[object Object]')
for label, raw in RAW_VALUES:
    error = {'message': 'Provider returned error', 'metadata': {'raw': raw}}
    test(S, f'HTTP error with {label} metadata.raw', streamed(test_model(), [user('hi')], [dict(status=400, type='application/json', body=json.dumps({'error': error}))]), raw_suffix(JS_STRING.get(label)))
    test(S, f'in-stream error with {label} metadata.raw', streamed(test_model(), [user('hi')], [sse([chunk(dict(content='x')), dict(error=error)])]), raw_suffix(JS_STRING.get(label)))

# provider-error-body-regression.test.ts, the openai-completions cases. The
# suite mocks the SDK's APIError; here a real 403 carries the same parsed
# body through the SDK error path (the Responses and Bedrock cases are
# pending, see the inventory).
S = 'provider-error-body-regression'
ERROR_BODY_MODEL = model_of(dict(id='test-model', name='Test Model', provider='openrouter', reasoning=False, input=['text'], cost=COST, contextWindow=1000, maxTokens=100))


def forbidden(error):
    return [dict(status=403, type='application/json', body=json.dumps({'error': error}))]


def surfaces_body(results):
    value = message(results[0])
    equal(value['stopReason'], 'error')
    assert '403' in value['errorMessage'], value['errorMessage']
    assert 'blocked by gateway WAF' in value['errorMessage'], value['errorMessage']
    assert value['errorMessage'] != '403 status code (no body)', value['errorMessage']


def raw_once(results):
    text = message(results[0])['errorMessage']
    assert text.count('upstream WAF blocked policy XYZ') == 1, text


test(S, 'openai-completions (body-blind text) surfaces status + body', streamed(ERROR_BODY_MODEL, [user([dict(type='text', text='hi')], 0)], forbidden('blocked by gateway WAF'), systemPrompt='', tools=[]), surfaces_body)
test(S, 'openai-completions does not double-print the OpenRouter metadata.raw extra', streamed(ERROR_BODY_MODEL, [user([dict(type='text', text='hi')], 0)], forbidden({'message': 'Provider returned error', 'code': 403, 'metadata': {'raw': 'upstream WAF blocked policy XYZ'}}), systemPrompt='', tools=[]), raw_once)

S = 'native: mid-stream abort'


def aborted(results):
    value = message(results[0])
    equal(value['stopReason'], 'aborted')
    equal([e['type'] for e in results[0]['events']][-1], 'error')
    equal(results[0]['events'][-1]['reason'], 'aborted')
    equal(value['content'], [dict(type='text', text='partial')])


STALLED = dict(status=200, parts=['data: ' + json.dumps(chunk(dict(content='partial'))) + '\n\n', 'data: ' + json.dumps(chunk({}, 'stop')) + '\n\ndata: [DONE]\n\n'], stall=3)
test(S, 'aborting after the first text delta ends the stream as aborted', fixture('stream', test_model(), [user('hi')], [STALLED], dict(apiKey='test'), abortAfter='text_delta'), aborted)
test(S, 'aborting through streamSimple after the first text delta', fixture('simple', test_model(), [user('hi')], [STALLED], dict(apiKey='test'), abortAfter='text_delta'), aborted)

# Supplementary differential streams
# ----------------------------------

rng = random.Random(20260925)
SUPPLEMENTARY = []
LARK = tool('grammar', 'Grammar tool', dict(input=dict(type='string')), constrainedSampling=dict(type='grammar', variants=dict(openai_lark='start: /[a-z]+/')))


def random_detail():
    kind = rng.choice(['reasoning.text', 'reasoning.summary', 'reasoning.encrypted', 'bogus'])
    value = {'type': kind}
    if kind == 'reasoning.text':
        value['text'] = rng.choice(['a', 'b ', ''])
        if rng.random() < 0.4:
            value['signature'] = rng.choice(['sig', None, ''])
    elif kind == 'reasoning.summary':
        value['summary'] = rng.choice(['s1', ' s2'])
    elif kind == 'reasoning.encrypted':
        value['data'] = 'enc'
    for key in ('id', 'format', 'index'):
        if rng.random() < 0.4:
            value[key] = {'id': rng.choice(['r1', None]), 'format': rng.choice(['f', '']), 'index': rng.choice([0, 1])}[key]
    return value


def random_tool_delta():
    value = {}
    if rng.random() < 0.8:
        value['index'] = rng.choice([0, 1])
    if rng.random() < 0.6:
        value['id'] = rng.choice(['call_a', 'call_b', 'call_c', ''])
    if rng.random() < 0.7:
        value['function'] = {k: v for k, v in dict(name=rng.choice(['read', None, '']), arguments=rng.choice(['{"path":', '"x"}', '', '{"a":1}'])).items() if rng.random() < 0.8}
    if rng.random() < 0.3:
        value['custom'] = {k: v for k, v in dict(name=rng.choice(['grammar', 'other']), input=rng.choice(['ab', 'c\\u00e9', ''])).items() if rng.random() < 0.8}
    return value


def random_chunk():
    delta = {}
    if rng.random() < 0.5:
        delta['content'] = rng.choice(['Hello', ' world', '', 'é\U0001F600'])
    for field in ('reasoning_content', 'reasoning', 'reasoning_text'):
        if rng.random() < 0.2:
            delta[field] = rng.choice(['think', ''])
    if rng.random() < 0.4:
        delta['tool_calls'] = [random_tool_delta() for _ in range(rng.randrange(1, 3))]
    if rng.random() < 0.25:
        delta['reasoning_details'] = [random_detail() for _ in range(rng.randrange(1, 3))]
    value = dict(id=rng.choice(['chatcmpl-x', '', 'chatcmpl-y']), choices=[dict(index=0, delta=delta, finish_reason=None)])
    if rng.random() < 0.3:
        value['model'] = rng.choice(['m', 'routed/model', ''])
    if rng.random() < 0.15:
        value['usage'] = dict(prompt_tokens=rng.randrange(20), completion_tokens=rng.randrange(20), prompt_tokens_details=dict(cached_tokens=rng.randrange(5)), completion_tokens_details=dict(reasoning_tokens=rng.randrange(5)))
    return value


for index in range(90):
    chunks = [random_chunk() for _ in range(rng.randrange(1, 7))]
    ending = rng.choice(['stop', 'tool_calls', 'length', 'content_filter', 'weird', None, 'null-chunk', 'error-payload'])
    if ending == 'null-chunk':
        chunks.append('null')
    elif ending == 'error-payload':
        chunks.append(dict(error=dict(message='upstream failed', metadata=dict(raw='raw provider text'))))
    elif ending is not None:
        chunks.append(dict(id='chatcmpl-x', choices=[dict(index=0, delta={}, finish_reason=ending)], usage=dict(prompt_tokens=7, completion_tokens=3, prompt_cache_hit_tokens=2)))
    compat = dict(supportsFinishReason=rng.random() < 0.7, supportsOpenAIGrammarTools=rng.random() < 0.5)
    provider = rng.choice(['openai', 'opencode-go', 'local'])
    model = model_of(dict(id='m', name='M', provider=provider, reasoning=True, input=['text'], cost=dict(input=1, output=2, cacheRead=0.5, cacheWrite=0), contextWindow=128000, maxTokens=4096, compat=compat))
    SUPPLEMENTARY.append(streamed(model, [user('go')], [sse(chunks, done=rng.random() < 0.8)], tools=[READ, LARK]))
for status, body_type in itertools.product([400, 401, 404, 429, 500, 503], ['json', 'text', 'empty', 'metadata']):
    body = {'json': json.dumps({'error': {'message': 'bad things', 'type': 'invalid_request_error'}}), 'text': 'plain failure', 'empty': '', 'metadata': json.dumps({'error': {'message': 'Provider returned error', 'metadata': {'raw': 'raw upstream detail'}}})}[body_type]
    SUPPLEMENTARY.append(streamed(test_model(), [user('hi')], [dict(status=status, type='application/json', body=body)]))

# Running
# -------

HEADERS = ('authorization', 'user-agent', 'x-stainless-retry-count', 'x-stainless-timeout', 'content-type', 'accept', 'x-initiator', 'openai-intent', 'copilot-vision-request', 'editor-version')


def masked(value):
    value = copy.deepcopy(value)
    if isinstance(value, dict):
        if 'timestamp' in value and 'role' in value:
            value['timestamp'] = 0
        for key in list(value):
            value[key] = masked(value[key])
    elif isinstance(value, list):
        value = [masked(item) for item in value]
    return value


def comparable(result):
    events = []
    for event in result['events']:
        event = {k: v for k, v in event.items() if k != 'partial'}
        events.append(masked(event))
    return dict(events=events, message=masked(result['message']))


def comparable_requests(requests):
    return [dict(path=r['path'], body=r['body'], headers={k: r['headers'].get(k) for k in HEADERS}) for r in requests]


def reset(fixtures):
    for f in fixtures:
        Handler.scripts[f['id']] = f['script']
        Handler.counters[f['id']] = 0
        Handler.received[f['id']] = []


def wire(f):
    return {k: v for k, v in f.items() if k not in ('script', 'id')}


def oracle(fixtures):
    reset(fixtures)
    results = json.loads(subprocess.check_output(['bun', 'tests/openai_completions_stream_reference.ts'], input=json.dumps({'cases': [wire(f) for f in fixtures]}), text=True, cwd=ROOT))
    for f, r in zip(fixtures, results):
        r['requests'] = Handler.received[f['id']]
    return results


def encode(value):
    return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=True, separators=(',', ':')))


def decode(line):
    return json.loads(''.join(chr(int(part)) for part in line.split(',')))


def native(command, fixtures):
    reset(fixtures)
    run = subprocess.run(command + [encode(wire(f)) for f in fixtures], cwd=ROOT, capture_output=True, text=True, timeout=600)
    assert run.returncode == 0, (run.stdout[-2000:], run.stderr[-4000:])
    results = [decode(line[2:]) for line in run.stdout.splitlines() if line.startswith('R ')]
    assert len(results) == len(fixtures), run.stdout[-2000:]
    for f, r in zip(fixtures, results):
        r['requests'] = Handler.received[f['id']]
    return results


def convert_results(command, fixtures):
    wires = [dict(wire(f)) for f in fixtures]
    expected = json.loads(subprocess.check_output(['bun', 'tests/openai_completions_request_reference.ts'], input=json.dumps({'cases': wires}), text=True, cwd=ROOT))
    run = subprocess.run(command + [encode(w) for w in wires], cwd=ROOT, capture_output=True, text=True, timeout=600)
    assert run.returncode == 0, run.stderr[-2000:]
    actual = [decode(line[2:]) for line in run.stdout.splitlines() if line.startswith('R ')]
    for want, got in zip(expected, actual):
        assert want == got, ('convertMessages differs', got, want)
    return actual


def differential(expected, actual):
    assert comparable(actual) == comparable(expected), ('stream differs', json.dumps(comparable(actual))[:3000], json.dumps(comparable(expected))[:3000])
    assert comparable_requests(actual['requests']) == comparable_requests(expected['requests']), ('requests differ', comparable_requests(actual['requests']), comparable_requests(expected['requests']))


selected = [c for c in CASES if not arguments.only or arguments.only in c['suite'] + '/' + c['name']]

if not arguments.no_build:
    for entry, prefix in ((ENTRY, arguments.prefix), (REQUEST_ENTRY, arguments.prefix + '-request')):
        if any(name.startswith('native') for name in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable, 'scripts/run-rss-guarded.py', '--stats', prefix + '-build.json', '--', 'sh', 'scripts/build-pure.sh', entry, prefix], cwd=ROOT, check=True)
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', entry, '-o', prefix + '.js'], cwd=ROOT, check=True)

failures = 0
for backend in arguments.backends:
    command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
    request_command = ['bun', arguments.prefix + '-request.js'] if backend == 'bun' else [arguments.prefix + '-request', '--threads', backend[-1]]
    passed = 0
    for c in selected:
        try:
            if c['fixtures'][0].get('convert'):
                c['check'](convert_results(request_command, c['fixtures']))
            else:
                expected = oracle(c['fixtures'])
                actual = native(command, c['fixtures'])
                for want, got in zip(expected, actual):
                    differential(want, got)
                if c['follow']:
                    second = c['follow'](expected[0])
                    want = oracle([second])[0]
                    got = native(command, [second])[0]
                    differential(want, got)
                    expected, actual = expected + [want], actual + [got]
                c['check'](actual)
            passed += 1
        except AssertionError as error:
            failures += 1
            print(f'FAIL {backend} {c["suite"]} > {c["name"]}: {str(error)[:3000]}')
    print(f'{backend}: {passed} of {len(selected)} named stream cases match upstream')
    if not arguments.only:
        mismatches = 0
        expected = oracle(SUPPLEMENTARY)
        for start in range(0, len(SUPPLEMENTARY), 16):
            chunk_cases = SUPPLEMENTARY[start:start + 16]
            for offset, (want, got) in enumerate(zip(expected[start:start + 16], native(command, chunk_cases))):
                try:
                    differential(want, got)
                except AssertionError as error:
                    mismatches += 1
                    if mismatches <= 5:
                        print(f'FAIL {backend} supplementary #{start + offset}: {str(error)[:3000]}')
        failures += mismatches
        print(f'{backend}: {len(SUPPLEMENTARY) - mismatches} of {len(SUPPLEMENTARY)} supplementary streams match upstream')
server.shutdown()
sys.exit(1 if failures else 0)
