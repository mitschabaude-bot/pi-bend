#!/usr/bin/env python3
"""pi-mono's live provider suites, replayed over loopback.

Upstream runs stream, abort, empty, tokens, total-tokens, unicode-surrogate,
context-overflow, tool-call-without-result and cross-provider-handoff against
real provider endpoints when credentials are present. This check runs their
test functions for the APIs the CLI uses (Anthropic Messages, Gemini, OpenAI
Chat Completions, OpenAI Responses, Azure OpenAI Responses and Codex) against
tests/live_replay_server.py, which replays each provider's wire format, and
executes every request twice: through pinned pi-mono
(tests/live_replay_reference.ts) and through the port's provider streams
(packages/coding-agent/test/live-replay.bend). Each test passes when the
upstream assertions hold for both executors, both sent the same requests
(path and JSON body), and both produced the same events and final messages.

The rows are read from the pinned test files: every `it` whose model uses
one of those APIs is run with the options its test passes. Rows on other APIs
(Bedrock, Mistral, Vertex), the Codex WebSocket transport, local servers and
upstream `it.skip` stay pending; `--pending` lists them with the reason.

Adaptations, documented per suite in tests/upstream-inventory.json:
- A replayed model answers from a script, so assertions about what a real
  model says (e.g. "Hello test successful") hold by construction; what the
  check establishes is the client side: request payloads, stream decoding,
  abort handling, usage accounting, error mapping, message transformation.
  Replies follow each provider's documented stream shape and quirks (early
  usage, overflow error texts from upstream's utils/overflow.ts examples).
- compat.ts's environment-key fallback is applied by the harness: each case
  carries the key the suite's environment (or token) would supply.
- Codex cases select the SSE transport (upstream's default "auto" tries
  WebSocket first; the port has only SSE). Upstream zstd-compresses Codex
  bodies and the port does not; the server decodes before comparing.
- handleThinking's random operand is fixed so both executors send the same
  request.
- Provider-side rejections (lone surrogates, tool calls without results) are
  modelled by the server for exactly the defects the suites guard against.
- Unpaired surrogates reach the port through a marker (its strict JSON
  decoder rejects them, an approved adaptation); those rows and the
  multi-megabyte context-overflow prompts run on native backends only.
- testAbortSignal returns at the first event after abort(), so upstream's
  post-loop assertions never run; the aborted stream is still compared.
- The reference runs under Bun, whose fetch abort text differs from Node's;
  both are treated as the runtime's AbortError. Remaining differences under
  decision are reported as KNOWN, not PASS.
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from upstream_pin import UPSTREAM
from live_replay_server import Reply, Server, usage

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/coding-agent/test/live-replay.bend'


def jwt(account='acc_replay'):
    payload = base64.urlsafe_b64encode(json.dumps({'https://api.openai.com/auth': {'chatgpt_account_id': account}}).encode()).decode().rstrip('=')
    return f'eyJhbGciOiJub25lIn0.{payload}.sig'


# The keys the suites' environment would supply (compat.ts falls back to
# getEnvApiKey; OAuth suites pass their tokens explicitly).
KEYS = {
    'anthropic': 'sk-ant-api03-replay',
    'anthropicOAuthToken': 'sk-ant-oat01-replay',
    'githubCopilotToken': 'tid=replay;exp=4102444800;proxy-ep=proxy.individual.githubcopilot.com',
    'openaiCodexToken': jwt(),
}
KEYS['openai-codex'] = KEYS['openaiCodexToken']
KEYS['github-copilot'] = KEYS['githubCopilotToken']

API_TAG = {'anthropic-messages': 'anthropic', 'google-generative-ai': 'google', 'openai-completions': 'completions', 'openai-responses': 'responses', 'azure-openai-responses': 'azure', 'openai-codex-responses': 'codex'}

# Upstream catalog metadata, filled by catalog_metadata().
META = {}


class Model:
    def __init__(self, provider, id, override=None, key=None):
        meta = META[(provider, id)]
        self.provider, self.id, self.override = provider, id, override
        self.api = override or meta['api']
        self.reasoning, self.input, self.cost_input, self.context_window = meta['reasoning'], meta['input'], meta['cost'], meta['contextWindow']
        self.key = key or KEYS.get(provider, f'replay-{provider}-key')

    @property
    def tag(self):
        return API_TAG[self.api]


# Scripted replies
# ----------------
SIGNATURES = {'anthropic': 'sig-anthropic-replay', 'responses': 'enc-replay', 'azure': 'enc-replay', 'codex': 'enc-replay'}
TOOL_IDS = {'anthropic': 'toolu_replay_{}', 'completions': 'call_replay_{}', 'responses': 'call_replay_{}', 'azure': 'call_replay_{}', 'codex': 'call_replay_{}', 'google': ''}

# The model each scenario (`<kind>.<index>`) runs against, for provider quirks.
SCENARIO_MODELS = {}


def thinking(api, text):
    if api == 'google':
        return [('thinking', text, '')]
    return [('thinking', text, SIGNATURES.get(api, ''))]


def tool(api, n, name, arguments):
    block = ('tool', TOOL_IDS[api].format(n), name, json.dumps(arguments))
    return block + ('c2lnLWdvb2dsZQ==',) if api == 'google' else block


def text(value):
    return [('text', value)]


def reasoned(model, api, value):
    """Thinking blocks for models that stream reasoning."""
    return thinking(api, value) if model is None or model.reasoning else []


def early_usage(model, input, output):
    """Anthropic-format providers differ in what message_start reports."""
    provider = model.provider if model else ''
    if provider in ('minimax', 'minimax-cn', 'vercel-ai-gateway'):
        return usage(input=0, output=0), False
    if provider == 'kimi-coding':
        return usage(input=input, output=0), False
    return usage(input=input, output=output), True


# context-overflow.test.ts: each provider's documented overflow response
# (the examples in upstream's utils/overflow.ts).
def overflow_reply(model, api):
    provider = model.provider
    window = int(model.context_window)
    if provider == 'cerebras':
        return Reply([], error=(None,), status=400)
    if provider == 'zai':
        return Reply(text('ok'), usage=usage(input=window + 10000, output=1))
    if provider.startswith('xiaomi'):
        return Reply([], stop='length', usage=usage(input=window, output=0))
    message = {
        'anthropic': 'prompt is too long: 213462 tokens > 200000 maximum',
        'github-copilot': f'prompt token count of {window + 10000} exceeds the limit of {window}',
        'xai': f"This model's maximum prompt length is {window} but the request contains {window + 10000} tokens",
        'groq': 'Please reduce the length of the messages or completion.',
        'huggingface': f"Input length ({window + 10000}) exceeds model's maximum context length ({window}).",
        'together': f"The input ({window + 10000} tokens) is longer than the model's context length ({window} tokens).",
        'minimax': 'invalid params, context window exceeds limit',
        'kimi-coding': f'Your request exceeded model token limit: {window} (requested: {window + 10000})',
        'openrouter': f"This endpoint's maximum context length is {window} tokens. However, you requested about {window + 10000} tokens.",
        'vercel-ai-gateway': f'The input token count ({window + 10000}) exceeds the maximum number of tokens allowed ({window}).',
        'google': f'The input token count ({window + 10000}) exceeds the maximum number of tokens allowed ({window}).',
    }.get(provider)
    if message is None and provider.startswith('qwen'):
        message = f'Range of input length should be [1, {window}]'
    if message is None:
        message = {'completions': f"This model's maximum context length is {window} tokens. However, your messages resulted in {window + 10000} tokens. Please reduce the length of the messages."}.get(api, 'Your input exceeds the context window of this model. Please adjust your input and try again.')
    return Reply([], error=(message, 'context_length_exceeded'))


def script(scenario, api, index, body):
    kind = scenario.split('.')[0]
    model = SCENARIO_MODELS.get(scenario)
    if kind == 'basic':
        return Reply(text(['Hello test successful', 'Goodbye test successful'][min(index, 1)]))
    if kind == 'tool':
        return Reply([tool(api, 1, 'math_operation', {'a': 15, 'b': 27, 'operation': 'add'})], stop='tool')
    if kind == 'streaming':
        return Reply(text('1\n2\n3'), chunk=2)
    if kind == 'thinking':
        return Reply(thinking(api, 'Let me add the numbers step by step.') + text('The result is 54.'))
    if kind == 'image':
        return Reply(text('I see a red circle.'))
    if kind == 'multiturn':
        if index == 0:
            return Reply(reasoned(model, api, 'I need two calculations.') + [tool(api, 1, 'math_operation', {'a': 42, 'b': 17, 'operation': 'multiply'}), tool(api, 2, 'math_operation', {'a': 453, 'b': 434, 'operation': 'add'})], stop='tool')
        return Reply(text('42 * 17 = 714 and 453 + 434 = 887.'))
    if kind == 'abort':
        return Reply(text('Adding 15 and 27 gives 42. Here are fifty names: A'), chunk=10, hang=True)
    if kind == 'tokens':
        early, _ = early_usage(model, 30, 1)
        return Reply(text(('Stanza of the forest, river and sky. ' * 30)[:1000]), chunk=50, hang=True, usage=early)
    if kind == 'total':
        if api == 'anthropic':
            first, second = usage(input=50, output=1, cache_write=1150), usage(input=60, output=1, cache_read=1150)
        else:
            first, second = usage(input=1200, output=1), usage(input=60, output=1, cache_read=1150)
        return Reply(text('4'), usage=first) if index == 0 else Reply(text('6'), usage=second)
    if kind == 'empty':
        return Reply(text('ok'))
    if kind == 'emptyassistant':
        return Reply(text("I'm here to help."))
    if kind == 'unicode':
        return Reply(text('Summary of the tool result.'))
    if kind == 'overflow':
        return overflow_reply(model, api)
    if kind == 'toolnores':
        if index == 0:
            return Reply([tool(api, 1, 'calculate', {'expression': '25 * 18'})], stop='tool')
        return Reply(text('2 + 2 = 4.'))
    if kind == 'handoffgen':
        if index == 0:
            return Reply(reasoned(model, api, 'I should call the tool with 21.') + [tool(api, 1, 'double_number', {'value': 21})], stop='tool')
        return Reply(text('The result is 42.'))
    if kind == 'handoff':
        return Reply(text('Hello, handoff successful!'))
    raise AssertionError(kind)


# Executors
# ---------
def decoded(points):
    return ''.join(chr(int(p)) for p in points.split(',')) if points else ''


class Failed(AssertionError):
    pass


class Executor:
    def __init__(self, name, command, base):
        self.name, self.command, self.base = name, command, base
        self.outputs = []

    def __call__(self, case):
        text = json.dumps(case)
        if self.name != 'upstream':
            # See restoredText in the executor: U+E000 stands for U+D83D.
            text = re.sub(r'\\ud83d(?!\\ud[c-f])', r'\\ue000', text)
        with tempfile.NamedTemporaryFile('w', suffix='.json', prefix='live-replay-') as file:
            file.write(text)
            file.flush()
            run = subprocess.run(self.command + [self.base, file.name], cwd=ROOT, capture_output=True, text=True, timeout=600)
        if run.returncode != 0:
            raise Failed(f'{self.name} exited {run.returncode}: {run.stderr[-1500:]}')
        events, message, thrown, overflowed = [], None, None, None
        for line in run.stdout.splitlines():
            if line.startswith('E '):
                kind, _, delta = line[2:].partition(':')
                events.append((kind, decoded(delta) if kind.endswith('_delta') else None))
            elif line.startswith('R '):
                message = json.loads(decoded(line[2:]))
            elif line.startswith('T '):
                thrown = line[2:]
            elif line.startswith('O '):
                overflowed = line[2:] == 'true'
        result = dict(events=events, message=message, thrown=thrown, overflow=overflowed)
        self.outputs.append(result)
        if thrown is not None:
            raise Failed(f'{self.name} threw: {thrown}')
        return result


# Suite functions (pi-mono f07218c4d packages/ai/test/*.test.ts)
# --------------------------------------------------------------
def expect(condition, message):
    if not condition:
        raise Failed(message)


def user(content, timestamp=1):
    return {'role': 'user', 'content': content, 'timestamp': timestamp}


def case(model, run, context, options=None, entry='stream', **extra):
    # Codex defaults to transport "auto" (WebSocket first, then SSE); the port
    # has only the SSE transport, so Codex cases select it explicitly.
    transport = {'transport': 'sse'} if model.api == 'openai-codex-responses' else {}
    return dict(run=run, provider=model.provider, model=model.id, api=model.override, entry=entry, context=context, options={'apiKey': model.key, **transport, **(options or {})}, **extra)


def texts(message):
    return ''.join(block.get('text', '') for block in message['content'] if block['type'] == 'text')


CALCULATOR = {'name': 'math_operation', 'description': 'Perform basic arithmetic operations', 'parameters': {'type': 'object', 'required': ['a', 'b', 'operation'], 'properties': {'a': {'type': 'number', 'description': 'First number'}, 'b': {'type': 'number', 'description': 'Second number'}, 'operation': {'type': 'string', 'enum': ['add', 'subtract', 'multiply', 'divide'], 'description': "The operation to perform. One of 'add', 'subtract', 'multiply', 'divide'."}}}}


def basicTextGeneration(ex, model, run, options=None):
    context = {'systemPrompt': 'You are a helpful assistant. Be concise.', 'messages': [user("Reply with exactly: 'Hello test successful'")]}
    response = ex(case(model, run, context, options))['message']
    expect(response['role'] == 'assistant' and response['content'], 'no content')
    expect(response['usage']['input'] + response['usage']['cacheRead'] > 0 and response['usage']['output'] > 0, response['usage'])
    expect(not response.get('errorMessage') and 'Hello test successful' in texts(response), response)
    context['messages'] += [response, user("Now say 'Goodbye test successful'")]
    second = ex(case(model, run, context, options))['message']
    expect(second['usage']['input'] + second['usage']['cacheRead'] > 0 and second['usage']['output'] > 0, second['usage'])
    expect(not second.get('errorMessage') and 'Goodbye test successful' in texts(second), second)


def handleToolCall(ex, model, run, options=None):
    context = {'systemPrompt': 'You are a helpful assistant that uses tools when asked.', 'messages': [user('Calculate 15 + 27 using the math_operation tool.')], 'tools': [CALCULATOR]}
    result = ex(case(model, run, context, options))
    kinds = [kind for kind, _ in result['events']]
    expect('toolcall_start' in kinds and 'toolcall_delta' in kinds and 'toolcall_end' in kinds, kinds)
    accumulated = ''.join(delta for kind, delta in result['events'] if kind == 'toolcall_delta')
    json.loads(accumulated)
    response = result['message']
    expect(response['stopReason'] == 'toolUse', response['stopReason'])
    call = next(block for block in response['content'] if block['type'] == 'toolCall')
    expect(call['name'] == 'math_operation' and call['id'], call)
    expect(call['arguments']['a'] == 15 and call['arguments']['b'] == 27 and call['arguments']['operation'] in ('add', 'subtract', 'multiply', 'divide'), call)


def handleStreaming(ex, model, run, options=None):
    context = {'messages': [user('Count from 1 to 3')], 'systemPrompt': 'You are a helpful assistant.'}
    result = ex(case(model, run, context, options))
    kinds = [kind for kind, _ in result['events']]
    expect('text_start' in kinds and 'text_end' in kinds, kinds)
    expect(''.join(delta for kind, delta in result['events'] if kind == 'text_delta'), 'no text deltas')
    expect(any(block['type'] == 'text' for block in result['message']['content']), result['message'])


def handleThinking(ex, model, run, options=None):
    # Upstream asks about a random number; the replayed model ignores it, so
    # the prompt is fixed to keep both executors' requests comparable.
    context = {'messages': [user('Think long and hard about 27 + 27. Think step by step. Then output the result.')], 'systemPrompt': 'You are a helpful assistant.'}
    result = ex(case(model, run, context, options))
    response = result['message']
    kinds = [kind for kind, _ in result['events']]
    expect(response['stopReason'] == 'stop', f"Error: {response.get('errorMessage')}")
    expect('thinking_start' in kinds and 'thinking_end' in kinds, kinds)
    expect(''.join(delta for kind, delta in result['events'] if kind == 'thinking_delta'), 'no thinking deltas')
    expect(any(block['type'] == 'thinking' for block in response['content']), response)


def handleImage(ex, model, run, options=None):
    if 'image' not in model.input:
        return
    image = base64.b64encode((UPSTREAM / 'packages/ai/test/data/red-circle.png').read_bytes()).decode()
    context = {'messages': [user([{'type': 'text', 'text': 'What do you see in this image? Please describe the shape (circle, rectangle, square, triangle, ...) and color (red, blue, green, ...). You MUST reply in English.'}, {'type': 'image', 'data': image, 'mimeType': 'image/png'}])], 'systemPrompt': 'You are a helpful assistant.'}
    response = ex(case(model, run, context, options))['message']
    expect(response['content'], 'no content')
    lower = texts(response).lower()
    expect('red' in lower and 'circle' in lower, lower)


def multiTurn(ex, model, run, options=None):
    context = {'systemPrompt': 'You are a helpful assistant that can use tools to answer questions.', 'messages': [user('Think about this briefly, then calculate 42 * 17 and 453 + 434 using the math_operation tool.')], 'tools': [CALCULATOR]}
    all_text, seen_thinking, seen_tools = '', False, False
    for _ in range(5):
        response = ex(case(model, run, context, options))['message']
        context['messages'].append(response)
        results = []
        for block in response['content']:
            if block['type'] == 'text':
                all_text += block['text']
            elif block['type'] == 'thinking':
                seen_thinking = True
            elif block['type'] == 'toolCall':
                seen_tools = True
                expect(block['name'] == 'math_operation' and block['id'] and block['arguments'], block)
                a, b, operation = block['arguments']['a'], block['arguments']['b'], block['arguments']['operation']
                value = a + b if operation == 'add' else a * b if operation == 'multiply' else 0
                results.append({'role': 'toolResult', 'toolCallId': block['id'], 'toolName': block['name'], 'content': [{'type': 'text', 'text': str(value)}], 'isError': False, 'timestamp': 1})
        context['messages'] += results
        expect(response['stopReason'] != 'error', f"Error: {response.get('errorMessage')}")
        if response['stopReason'] == 'stop':
            break
    expect(seen_thinking or seen_tools, 'no thinking or tool calls')
    expect('714' in all_text and '887' in all_text, all_text)


def testAbortSignal(ex, model, run, options=None):
    context = {'messages': [user('What is 15 + 27? Think step by step. Then list 50 first names.')], 'systemPrompt': 'You are a helpful assistant.'}
    # Upstream's loop returns at the first event after abort(), so its
    # assertions after the loop (and the follow-up request) never run; the
    # aborted stream is still compared between the executors.
    ex(case(model, run, context, options, abortAfterChars=50))


def testImmediateAbort(ex, model, run, options=None):
    context = {'messages': [user('Hello')]}
    response = ex(case(model, run, context, options, abortBefore=True))['message']
    expect(response['stopReason'] == 'aborted', response['stopReason'])


def testTokensOnAbort(ex, model, run, options=None):
    context = {'messages': [user('Write a long poem with 20 stanzas about the beauty of nature.')], 'systemPrompt': 'You are a helpful assistant.'}
    response = ex(case(model, run, context, options, abortAfterChars=1000))['message']
    expect(response['stopReason'] == 'aborted', response['stopReason'])
    u = response['usage']
    if model.api in ('openai-completions', 'mistral-conversations', 'openai-responses', 'azure-openai-responses', 'openai-codex-responses') or model.provider in ('zai', 'amazon-bedrock', 'vercel-ai-gateway'):
        expect(u['input'] == 0 and u['output'] == 0, u)
    elif model.provider == 'minimax':
        expect(u['input'] == 0 and u['output'] == 0, u)
    elif model.provider == 'kimi-coding':
        expect(u['input'] > 0 and u['output'] == 0, u)
    else:
        expect(u['input'] > 0 and u['output'] > 0, u)
        if model.cost_input > 0:
            expect(u['cost']['input'] > 0 and u['cost']['total'] > 0, u['cost'])


LONG_SYSTEM_PROMPT = 'You are a helpful assistant. Be concise in your responses.\n\nHere is some additional context that makes this system prompt long enough to trigger caching:\n\n' + '\n\n'.join(['Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.'] * 50) + '\n\nRemember: Always be helpful and concise.'


def testTotalTokensWithCache(ex, model, run, options=None):
    first_context = {'systemPrompt': LONG_SYSTEM_PROMPT, 'messages': [user('What is 2 + 2? Reply with just the number.')]}
    first = ex(case(model, run, first_context, options))['message']
    expect(first['stopReason'] == 'stop', first['stopReason'])
    second_context = {'systemPrompt': LONG_SYSTEM_PROMPT, 'messages': first_context['messages'] + [first, user('What is 3 + 3? Reply with just the number.')]}
    second = ex(case(model, run, second_context, options))['message']
    expect(second['stopReason'] == 'stop', second['stopReason'])
    return first['usage'], second['usage']


def assertTotalTokensEqualsComponents(u):
    expect(u['totalTokens'] == u['input'] + u['output'] + u['cacheRead'] + u['cacheWrite'], u)


def totalTokens(anthropic_cache=False):
    def test(ex, model, run, options=None):
        first, second = testTotalTokensWithCache(ex, model, run, options)
        assertTotalTokensEqualsComponents(first)
        assertTotalTokensEqualsComponents(second)
        if anthropic_cache:
            expect(second['cacheRead'] > 0 or second['cacheWrite'] > 0 or first['cacheWrite'] > 0, 'no cache activity')
    return test


def graceful(response, nonempty=False):
    expect(response['role'] == 'assistant', response)
    if response['stopReason'] == 'error':
        expect(response.get('errorMessage') is not None, response)
    else:
        expect(response['content'] is not None, response)
        if nonempty:
            expect(len(response['content']) > 0, response)


def testEmptyMessage(ex, model, run, options=None):
    graceful(ex(case(model, run, {'messages': [user([])]}, options))['message'])


def testEmptyStringMessage(ex, model, run, options=None):
    graceful(ex(case(model, run, {'messages': [user('')]}, options))['message'])


def testWhitespaceOnlyMessage(ex, model, run, options=None):
    graceful(ex(case(model, run, {'messages': [user('   \n\t  ')]}, options))['message'])


def zero_usage(input=0, total=0):
    return {'input': input, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': total, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}


def testEmptyAssistantMessage(ex, model, run, options=None):
    empty = {'role': 'assistant', 'content': [], 'api': model.api, 'provider': model.provider, 'model': model.id, 'usage': zero_usage(10, 10), 'stopReason': 'stop', 'timestamp': 1}
    context = {'messages': [user('Hello, how are you?'), empty, user('Please respond this time.')]}
    graceful(ex(case(model, run, context, options))['message'], nonempty=True)


EMOJI_TEXT = """Test with emoji 🙈 and other characters:
- Monkey emoji: 🙈
- Thumbs up: 👍
- Heart: ❤️
- Thinking face: 🤔
- Rocket: 🚀
- Mixed text: Mario Zechner wann? Wo? Bin grad äußersr eventuninformiert 🙈
- Japanese: こんにちは
- Chinese: 你好
- Mathematical symbols: ∑∫∂√
- Special quotes: "curly" 'quotes'"""

LINKEDIN_TEXT = """Post: Hab einen "Generative KI für Nicht-Techniker" Workshop gebaut.
Unanswered Comments: 2

=> {
  "comments": [
    {
      "author": "Matthias Neumayer's  graphic link",
      "text": "Leider nehmen das viel zu wenige Leute ernst"
    },
    {
      "author": "Matthias Neumayer's  graphic link",
      "text": "Mario Zechner wann? Wo? Bin grad äußersr eventuninformiert 🙈"
    }
  ]
}"""


def unicodeContext(model, call_id, tool_name, description, prompt, result_text, follow_up):
    assistant = {'role': 'assistant', 'content': [{'type': 'toolCall', 'id': call_id, 'name': tool_name, 'arguments': {}}], 'api': model.api, 'provider': model.provider, 'model': model.id, 'usage': zero_usage(), 'stopReason': 'toolUse', 'timestamp': 1}
    result = {'role': 'toolResult', 'toolCallId': call_id, 'toolName': tool_name, 'content': [{'type': 'text', 'text': result_text}], 'isError': False, 'timestamp': 1}
    return {'systemPrompt': 'You are a helpful assistant.', 'messages': [user(prompt), assistant, result, user(follow_up)], 'tools': [{'name': tool_name, 'description': description, 'parameters': {'type': 'object', 'properties': {}}}]}


def testEmojiInToolResults(ex, model, run, options=None):
    response = ex(case(model, run, unicodeContext(model, 'test_1', 'test_tool', 'A test tool', 'Use the test tool', EMOJI_TEXT, 'Summarize the tool result briefly.'), options))['message']
    expect(response['stopReason'] != 'error' and not response.get('errorMessage') and response['content'], response)


def testRealWorldLinkedInData(ex, model, run, options=None):
    response = ex(case(model, run, unicodeContext(model, 'linkedin_1', 'linkedin_skill', 'Get LinkedIn comments', 'Use the linkedin tool to get comments', LINKEDIN_TEXT, 'How many comments are there?'), options))['message']
    expect(response['stopReason'] != 'error' and not response.get('errorMessage') and any(block['type'] == 'text' for block in response['content']), response)


def testUnpairedHighSurrogate(ex, model, run, options=None):
    response = ex(case(model, run, unicodeContext(model, 'test_2', 'test_tool', 'A test tool', 'Use the test tool', 'Text with unpaired surrogate: \ud83d <- should be sanitized', 'What did the tool return?'), options))['message']
    expect(response['stopReason'] != 'error' and not response.get('errorMessage') and response['content'], response)


def overflow(row, model):
    """testContextOverflow and the row's own assertions."""
    body = row['body']
    patterns = re.findall(r'toMatch\(/(.*?)/i\)', body)

    def test(ex, model, run, options=None):
        result = ex(dict(case(model, run, {}, options), overflow=True))
        response = result['message']
        overflowed = result['overflow'] is True
        if 'result.stopReason === "error"' in body:
            # z.ai: an explicit overflow error, or a silent overflow in usage.
            if response['stopReason'] == 'error':
                if re.search('model_context_window_exceeded', response.get('errorMessage') or '', re.I):
                    expect(overflowed, 'isContextOverflow false')
            elif response['stopReason'] == 'stop':
                u = response['usage']
                if (u['input'] > 0 or u['cacheRead'] > 0) and u['input'] > model.context_window:
                    expect(overflowed, 'isContextOverflow false')
            return
        if 'toBe("length")' in body:
            expect(response['stopReason'] == 'length' and response['usage']['output'] == 0, response)
        else:
            expect(response['stopReason'] == 'error', response['stopReason'])
        for pattern in patterns:
            expect(re.search(pattern.replace('\\/', '/'), response.get('errorMessage') or '', re.I), (pattern, response.get('errorMessage')))
        expect(overflowed, f"isContextOverflow false: {response.get('errorMessage')}")
    test.overflow = True
    return test


CALCULATE = {'name': 'calculate', 'description': 'Evaluate mathematical expressions', 'parameters': {'type': 'object', 'required': ['expression'], 'properties': {'expression': {'type': 'string', 'description': 'The mathematical expression to evaluate'}}}}


def testToolCallWithoutResult(ex, model, run, options=None):
    context = {'systemPrompt': 'You are a helpful assistant. Use the calculate tool when asked to perform calculations.', 'messages': [user('Please calculate 25 * 18 using the calculate tool.')], 'tools': [CALCULATE]}
    first = ex(case(model, run, context, options))['message']
    context['messages'].append(first)
    expect(any(block['type'] == 'toolCall' for block in first['content']), first)
    context['messages'].append(user('Never mind, just tell me what is 2+2?'))
    second = ex(case(model, run, context, options))['message']
    expect(second['stopReason'] != 'error', second.get('errorMessage'))
    expect(second['content'], second)
    answer = ' '.join(block['text'] for block in second['content'] if block['type'] == 'text')
    expect(sum(1 for block in second['content'] if block['type'] == 'toolCall') or len(answer), second)
    expect(second['stopReason'] in ('stop', 'toolUse'), second['stopReason'])


DOUBLE = {'name': 'double_number', 'description': 'Doubles a number and returns the result', 'parameters': {'type': 'object', 'required': ['value'], 'properties': {'value': {'type': 'number', 'description': 'A number to double'}}}}


def simple(model, run, context, headers=None):
    options = {'reasoning': 'high'} if model.reasoning else {}
    if headers:
        options['headers'] = headers
    return case(model, run, context, options, entry='simple')


def generateContext(ex, pair, run):
    model, headers = pair
    user_message = user('Please double the number 21 using the double_number tool.')
    assistant = ex(simple(model, run, {'systemPrompt': 'You are a helpful assistant. Use the provided tool to complete the task.', 'messages': [user_message], 'tools': [DOUBLE]}, headers))['message']
    if assistant['stopReason'] == 'error':
        return None
    call = next((block for block in assistant['content'] if block['type'] == 'toolCall'), None)
    if call is None:
        return [user_message, assistant]
    result = {'role': 'toolResult', 'toolCallId': call['id'], 'toolName': call['name'], 'content': [{'type': 'text', 'text': '42'}], 'isError': False, 'timestamp': 1}
    final = ex(simple(model, run, {'systemPrompt': 'You are a helpful assistant.', 'messages': [user_message, assistant, result], 'tools': [DOUBLE]}, headers))['message']
    return None if final['stopReason'] == 'error' else [user_message, assistant, result, final]


class Handoff:
    """cross-provider-handoff.test.ts: beforeAll generates a fixture per
    provider/model pair (labels key the fixtures, so a repeated label keeps
    the later pair's messages, as upstream's record does); the two tests use
    them. Pairs on APIs the port does not replay are left out, as upstream
    leaves out pairs without credentials."""

    def __init__(self, pairs):
        self.pairs = pairs
        self.contexts = {}

    def run(self, kind, n, pair, ex):
        run = f'{kind}.h{n}'
        SCENARIO_MODELS[run] = pair[0]
        return f'{run}~{pair[0].tag}~{ex.name}'

    def fixtures(self, ex, model, run, options=None):
        contexts = self.contexts[ex.name] = {}
        for n, (label, pair) in enumerate(self.pairs):
            messages = generateContext(ex, pair, self.run('handoffgen', n, pair, ex))
            if messages and len(messages) >= 4:
                contexts[label] = messages
        expect(len(contexts) >= 2, contexts.keys())

    def targets(self, ex, model, run, options=None):
        failures = []
        contexts = self.contexts.get(ex.name, {})
        available = [(n, label, pair) for n, (label, pair) in enumerate(self.pairs) if label in contexts]
        for n, label, pair in available:
            others = [message for other, messages in contexts.items() if other != label for message in messages]
            messages = others + [user("Great, thanks for all that help! Now just say 'Hello, handoff successful!' to confirm you received everything.")]
            response = ex(simple(pair[0], self.run('handoff', n, pair, ex), {'systemPrompt': 'You are a helpful assistant.', 'messages': messages, 'tools': [DOUBLE]}, pair[1]))['message']
            if response['stopReason'] == 'error':
                failures.append((label, response.get('errorMessage')))
        expect(not failures, failures)


FUNCTIONS = {
    'basicTextGeneration': basicTextGeneration, 'handleToolCall': handleToolCall, 'handleStreaming': handleStreaming, 'handleThinking': handleThinking, 'handleImage': handleImage, 'multiTurn': multiTurn,
    'testAbortSignal': testAbortSignal, 'testImmediateAbort': testImmediateAbort, 'testTokensOnAbort': testTokensOnAbort,
    'testEmptyMessage': testEmptyMessage, 'testEmptyStringMessage': testEmptyStringMessage, 'testWhitespaceOnlyMessage': testWhitespaceOnlyMessage, 'testEmptyAssistantMessage': testEmptyAssistantMessage,
    'testEmojiInToolResults': testEmojiInToolResults, 'testRealWorldLinkedInData': testRealWorldLinkedInData, 'testUnpairedHighSurrogate': testUnpairedHighSurrogate,
    'testToolCallWithoutResult': testToolCallWithoutResult,
}


# The upstream suites
# -------------------
# Each `it` of the pinned suites becomes one row: its describe and test names,
# its model (getModel, with the suites' `api` override) and the options its
# test function receives. Rows on other APIs, transports or local servers stay
# pending with the reason.
SUITES = {
    'stream.test.ts': ('Generate E2E Tests', ['basicTextGeneration', 'handleToolCall', 'handleStreaming', 'handleThinking', 'handleImage', 'multiTurn']),
    'abort.test.ts': ('AI Providers Abort Tests', ['testAbortSignal', 'testImmediateAbort', 'testAbortThenNewMessage']),
    'tokens.test.ts': ('Token Statistics on Abort', ['testTokensOnAbort']),
    'empty.test.ts': ('AI Providers Empty Message Tests', ['testEmptyMessage', 'testEmptyStringMessage', 'testWhitespaceOnlyMessage', 'testEmptyAssistantMessage']),
    'unicode-surrogate.test.ts': ('AI Providers Unicode Surrogate Pair Tests', ['testEmojiInToolResults', 'testRealWorldLinkedInData', 'testUnpairedHighSurrogate']),
    'tool-call-without-result.test.ts': ('Tool Call Without Result Tests', ['testToolCallWithoutResult']),
    'total-tokens.test.ts': ('totalTokens field', ['testTotalTokensWithCache']),
    'context-overflow.test.ts': ('Context overflow error handling', ['testContextOverflow']),
}
BALANCED = r'(?:[^()]|\((?:[^()]|\([^()]*\))*\))*'


def upstream_rows():
    rows = []
    for file, (top, functions) in SUITES.items():
        source = (UPSTREAM / 'packages/ai/test' / file).read_text()
        for block in re.split(r'\n\tdescribe', source)[1:]:
            head = re.match(r'(?:\.skipIf\(' + BALANCED + r'\))?\(\s*"([^"]+)"', block)
            if not head:
                continue
            parts = re.split(r'\n\t+it(?=[.(])', block)
            shared_model = re.search(r'getModel\("([^"]+)", "([^"]+)"\)', parts[0])
            shared_api = re.search(r'api: "([a-z-]+)"|\.api = "([a-z-]+)"', parts[0])
            for part in parts[1:]:
                it = re.match(r'(\.skipIf\(' + BALANCED + r'\)|\.skip)?\(\s*"([^"]+)"', part)
                if not it:
                    continue
                model = re.search(r'getModel\("([^"]+)", "([^"]+)"\)', part) or shared_model
                api = re.search(r'api: "([a-z-]+)"|\.api = "([a-z-]+)"', part) or shared_api
                calls = re.findall(r'await (' + '|'.join(functions) + r')\((\w+)(?:, ((?:[^;])*?))?\);', part)
                rows.append(dict(file=file, name=f'{file} > {top} > {head.group(1)} > {it.group(2)}', describe=head.group(1), skipped=it.group(1) == '.skip', model=model.groups() if model else None, api=(api.group(1) or api.group(2)) if api else None, calls=calls, body=part, head=parts[0]))
    return rows


CEREBRAS_PREFERRED = ['gpt-oss-120b', 'zai-glm-4.7', 'llama3.1-8b']


def row_model(row):
    if row['model']:
        return row['model']
    if 'preferredCerebrasModelIds' in row['body'] + row['head']:
        return ('cerebras', next(id for id in CEREBRAS_PREFERRED if ('cerebras', id) in META))
    if 'candidate.id.startsWith("gemini-")' in row['body']:
        return ('github-copilot', META['copilot-gemini'])
    return None


def parse_options(expression, provider):
    """The suites' option literals (and the named option objects they use)."""
    expression = re.sub(r'\s+', ' ', expression or '').strip()
    if expression in ('', 'azureOptions', '{}'):
        return {}, None
    if expression in ('vertexOptions', 'wsOptions') or 'vertexOptions' in expression or 'wsOptions' in expression:
        return None, 'Vertex/WebSocket options (other API or transport)'
    if re.fullmatch(r'\w+', expression):
        return None, f'unresolved options object {expression}'
    options = {}
    key = re.search(r'apiKey: ([^,}]+)', expression) or re.fullmatch(r'([\w.!"-]+)', expression)
    if key:
        value = key.group(1).strip().rstrip('!')
        if value in KEYS:
            options['apiKey'] = KEYS[value]
        elif value.startswith('"'):
            options['apiKey'] = value.strip('"')
        elif value.startswith('process.env.'):
            options['apiKey'] = KEYS.get(provider, f'replay-{provider}-key')
    for name in ('reasoningEffort', 'effort', 'reasoning'):
        found = re.search(name + r': "([a-z]+)"', expression)
        if found:
            options[name] = found.group(1)
    if 'reasoning' in options:
        return None, 'streamSimple reasoning option (Bedrock)'
    if 'thinkingEnabled: true' in expression:
        options['thinkingEnabled'] = True
    budget = re.search(r'thinkingBudgetTokens: (\d+)', expression)
    if budget:
        options['thinkingBudgetTokens'] = int(budget.group(1))
    thinking = re.search(r'thinking: \{ enabled: true(?:, budgetTokens: (\d+))? \}', expression)
    if thinking:
        options['thinking'] = {'enabled': True, **({'budgetTokens': int(thinking.group(1))} if thinking.group(1) else {})}
    return options, None


def plan(row):
    """(function, model, options) for a replayed row, or (None, reason)."""
    if row['skipped']:
        return None, 'it.skip upstream'
    ids = row_model(row)
    if ids is None:
        return None, 'local server (Ollama/LM Studio/llama.cpp)'
    if tuple(ids) not in META or (row['api'] or META[tuple(ids)]['api']) not in API_TAG:
        return None, f'{ids[0]}/{ids[1]} uses an API this check does not replay'
    if len(row['calls']) != 1:
        return None, 'no single suite function call'
    function, _, expression = row['calls'][0]
    named = re.fullmatch(r'\s*(\w+)\s*', expression or '')
    if named and named.group(1) not in ('azureOptions', 'vertexOptions', 'wsOptions'):
        # A named options object declared in the test or its describe.
        declared = re.search(r'const ' + named.group(1) + r' = (\{[^;]*?\})(?: satisfies \w+)?;', row['body']) or re.search(r'const ' + named.group(1) + r' = (\{[^;]*?\})(?: satisfies \w+)?;', row['head'])
        if declared:
            expression = declared.group(1)
    options, reason = parse_options(expression, ids[0])
    if reason:
        return None, reason
    key = options.pop('apiKey', None)
    model = Model(ids[0], ids[1], row['api'], key)
    if function == 'testContextOverflow':
        return overflow(row, model), model, {}
    if function == 'testTotalTokensWithCache':
        return totalTokens('hasCache' in row['body']), model, options
    if function == 'testAbortThenNewMessage':
        return None, 'Bedrock only'
    return FUNCTIONS[function], model, options


def handoff_pairs():
    source = (UPSTREAM / 'packages/ai/test/cross-provider-handoff.test.ts').read_text()
    block = source[source.index('const PROVIDER_MODEL_PAIRS'):]
    block = block[:block.index('];')]
    pairs = []
    for provider, id, label, api, env in re.findall(r'\{\s*provider: "([^"]+)",\s*model: "([^"]+)",\s*label: "([^"]+)"(?:,\s*apiOverride: "([^"]+)")?(?:,\s*upstreamApiKeyEnv: "([^"]+)")?,?\s*\}', block):
        if (provider, id) in META and (api or META[(provider, id)]['api']) in API_TAG:
            headers = {'Authorization': f'Bearer replay-{env.lower()}'} if env else None
            pairs.append((label, (Model(provider, id, api or None), headers)))
    return pairs


# Comparison
# ----------
TIMESTAMP = re.compile(r'\d{13}')


def normalized(value):
    """Drops message timestamps and the millisecond clock in generated ids."""
    if isinstance(value, dict):
        return {key: normalized(item) for key, item in value.items() if key != 'timestamp'}
    if isinstance(value, list):
        return [normalized(item) for item in value]
    if isinstance(value, str):
        return TIMESTAMP.sub('<ms>', value)
    return value


def first_difference(want, have, path='$'):
    """The first place two JSON values differ, as `path: upstream != port`."""
    if isinstance(want, dict) and isinstance(have, dict):
        for key in list(want) + [key for key in have if key not in want]:
            if key not in have or key not in want or want[key] != have[key]:
                return first_difference(want.get(key, '<absent>'), have.get(key, '<absent>'), f'{path}.{key}')
    elif isinstance(want, list) and isinstance(have, list) and want != have:
        for index, (left, right) in enumerate(zip(want, have)):
            if left != right:
                return first_difference(left, right, f'{path}[{index}]')
        return f'{path}: length {len(want)} != {len(have)}'
    return f'{path}: {json.dumps(want)[:600]} != {json.dumps(have)[:600]}'


# The reference runs under Bun, whose fetch rejects an aborted body read with
# "The operation was aborted."; pi on Node reports "This operation was
# aborted", the text the port uses for that fetch error.
RUNTIME_ABORT = {'The operation was aborted.': 'This operation was aborted'}

# Differences that stay reported (KNOWN, not PASS) until they are decided.
KNOWN = [
    (('anthropic-messages', 'openai-codex-responses'), '$.message.errorMessage', 'This operation was aborted', 'Request was aborted',
     'abort during a pending body read: upstream surfaces the fetch AbortError; the port reports "Request was aborted" (upstream\'s text for an abort seen between reads, and what the mocked-fetch openai-codex-stream test asserts)'),
]


def runtime_normalized(output):
    message = output.get('message') or {}
    if message.get('errorMessage') in RUNTIME_ABORT:
        output = {**output, 'message': {**message, 'errorMessage': RUNTIME_ABORT[message['errorMessage']]}}
    return output


def known_difference(api, want, have):
    for apis, path, upstream, port, reason in KNOWN:
        if api in apis and (want.get('message') or {}).get('errorMessage') == upstream and (have.get('message') or {}).get('errorMessage') == port:
            return reason, {**have, 'message': {**have['message'], 'errorMessage': upstream}}
    return None, have


def request_view(request):
    try:
        body = json.loads(request['raw'])
    except ValueError:
        body = request['raw'].decode('utf-8', 'replace')
    return dict(path=TIMESTAMP.sub('<ms>', request['path']), body=normalized(body))


def differences(server, reference, port, runs, api, known):
    found = []
    port.compared = sum(len(server.requests.get(f'{run}~{port.name}', [])) for run in runs)
    for run in runs:
        want = [request_view(r) for r in server.requests.get(f'{run}~{reference.name}', [])]
        have = [request_view(r) for r in server.requests.get(f'{run}~{port.name}', [])]
        if want != have:
            found.append(f'requests of {run} differ at {first_difference(want, have)}')
    for want, have in zip(reference.outputs, port.outputs):
        want = runtime_normalized(want)
        reason, have = known_difference(api, want, have)
        if reason:
            known.append(reason)
        if normalized(want) != normalized(have):
            found.append(f'outputs differ at {first_difference(normalized(want), normalized(have))}')
    if len(reference.outputs) != len(port.outputs):
        found.append(f'request counts differ: upstream {len(reference.outputs)} port {len(port.outputs)}')
    return found


def native_only(function):
    """Cases the Bun backend cannot run (see docs/bend-issues.md)."""
    if function is testUnpairedHighSurrogate:
        return 'the JS backend cannot hold an unpaired surrogate (BEND-021)'
    if getattr(function, 'overflow', False):
        return 'the JS backend does not finish a multi-megabyte prompt'
    return None


def catalog_metadata(rows):
    """Upstream catalog facts for every model the rows and pairs use."""
    source = (UPSTREAM / 'packages/ai/test/cross-provider-handoff.test.ts').read_text()
    ids = {tuple(row['model']) for row in rows if row['model']}
    ids |= {(provider, id) for provider, id in re.findall(r'provider: "([^"]+)",\s*model: "([^"]+)"', source)}
    ids |= {('cerebras', id) for id in CEREBRAS_PREFERRED}
    script = f"""
const {{ getModel, getModels }} = await import({json.dumps(str(UPSTREAM / 'packages/ai/src/compat.ts'))});
const ids = JSON.parse(process.argv[1]);
const found = ids.map(([p, m]) => [p, m, getModel(p, m)]).filter(([, , x]) => x);
const gemini = getModels("github-copilot").find((candidate) => candidate.id.startsWith("gemini-"));
console.log(JSON.stringify({{ models: found.map(([p, m, x]) => [p, m, {{ api: x.api, reasoning: x.reasoning, input: x.input, cost: x.cost.input, contextWindow: x.contextWindow }}]), gemini: gemini && [gemini.id, {{ api: gemini.api, reasoning: gemini.reasoning, input: gemini.input, cost: gemini.cost.input, contextWindow: gemini.contextWindow }}] }}));
"""
    result = json.loads(subprocess.run(['bun', '-e', script, json.dumps(sorted(ids))], capture_output=True, text=True, check=True).stdout)
    for provider, id, meta in result['models']:
        META[(provider, id)] = meta
    if result['gemini']:
        META['copilot-gemini'] = result['gemini'][0]
        META[('github-copilot', result['gemini'][0])] = result['gemini'][1]


def run_test(index, name, function, model, options, kind, server, backends, commands):
    """Runs one test through upstream and each backend; returns (status, lines)."""
    run = f'{kind}.{index}'
    SCENARIO_MODELS[run] = model
    reference = Executor('upstream', ['bun', 'tests/live_replay_reference.ts'], server.base)
    problems, compared, known = [], [], []
    try:
        function(reference, model, f'{run}~{model.tag}~upstream', options)
    except Failed as error:
        problems.append(f'upstream: {error}')
    for backend in backends:
        skip = native_only(function) if backend == 'bun' else None
        if skip:
            compared.append(f'bun skipped: {skip}')
            continue
        port = Executor(backend, commands[backend], server.base)
        try:
            function(port, model, f'{run}~{model.tag}~{backend}', options)
        except Failed as error:
            problems.append(f'{backend}: {error}')
        prefix = 'handoff' if kind.startswith('handoff') else run
        runs = sorted({key.rsplit('~', 1)[0] for key in list(server.requests) if key.endswith('~upstream') and (key.startswith(run + '~') or (kind.startswith('handoff') and key.startswith(kind + '.h')))})
        problems += [f'{backend}: {item}' for item in differences(server, reference, port, runs, model.api, known)]
        compared.append(f'{backend} {port.compared}')
    if problems:
        return 'FAIL', [f'FAIL {name}'] + [f'  {problem[:3000]}' for problem in problems[:6]]
    if all(item.startswith('bun skipped') for item in compared):
        return 'SKIP', [f'SKIP {name}: {compared[0]}']
    if known:
        return 'KNOWN', [f'KNOWN {name}: {known[0]}']
    return 'PASS', [f'PASS {name} (requests compared: {", ".join(compared)})']


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--prefix', default='build/live-replay')
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--only', help='substring of the test names to run')
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--pending', action='store_true', help='list the rows left pending, with reasons')
    arguments = parser.parse_args()
    rows = upstream_rows()
    catalog_metadata(rows)
    tests, pending = [], []
    for row in rows:
        planned = plan(row)
        if planned[0] is None:
            pending.append((row['name'], planned[1]))
        else:
            tests.append((row['name'],) + planned + ({'testAbortSignal': 'abort', 'testImmediateAbort': 'immediate', 'testTokensOnAbort': 'tokens', 'testEmptyAssistantMessage': 'emptyassistant', 'basicTextGeneration': 'basic', 'handleToolCall': 'tool', 'handleStreaming': 'streaming', 'handleThinking': 'thinking', 'handleImage': 'image', 'multiTurn': 'multiturn', 'testToolCallWithoutResult': 'toolnores'}.get(row['calls'][0][0]) or {'testContextOverflow': 'overflow', 'testTotalTokensWithCache': 'total'}.get(row['calls'][0][0]) or ('unicode' if row['file'].startswith('unicode') else 'empty'),))
    handoff = Handoff(handoff_pairs())
    top = 'cross-provider-handoff.test.ts > Cross-Provider Handoff'
    first = handoff.pairs[0][1][0]
    tests += [(f'{top} > should have at least 2 fixtures to test handoffs', handoff.fixtures, first, None, 'handoffgen'), (f'{top} > should handle cross-provider handoffs for each target', handoff.targets, first, None, 'handoff')]
    if arguments.pending:
        for name, reason in pending:
            print(f'PENDING {name}: {reason}')
    if not arguments.no_build:
        if 'bun' in arguments.backends:
            subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
        if any(b.startswith('native') for b in arguments.backends):
            subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    commands = {'bun': ['bun', arguments.prefix + '.js'], 'native-1': [arguments.prefix, '--threads', '1'], 'native-4': [arguments.prefix, '--threads', '4']}
    selected = [(index, test) for index, test in enumerate(tests) if not arguments.only or arguments.only in test[0]]
    counts = {}
    with Server(script) as server:
        # Handoff fixtures and targets share state, so they run in order after
        # the independent tests.
        independent = [(index, test) for index, test in selected if not test[4].startswith('handoff')]
        ordered = [(index, test) for index, test in selected if test[4].startswith('handoff')]
        with ThreadPoolExecutor(max_workers=arguments.jobs) as pool:
            futures = [pool.submit(run_test, index, *test, server, arguments.backends, commands) for index, test in independent]
            outcomes = [future.result() for future in futures]
        outcomes += [run_test(index, *test, server, arguments.backends, commands) for index, test in ordered]
        for status, lines in outcomes:
            counts[status] = counts.get(status, 0) + 1
            print('\n'.join(lines))
    print(f"{counts.get('PASS', 0)} passed, {counts.get('KNOWN', 0)} known differences, {counts.get('SKIP', 0)} skipped on every backend run, {counts.get('FAIL', 0)} failed; {len(pending)} upstream tests pending (--pending lists them)")
    sys.exit(1 if counts.get('FAIL') else 0)


if __name__ == '__main__':
    main()
