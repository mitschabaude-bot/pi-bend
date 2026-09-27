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

# Verbatim response bodies for `raw.<index>` scenarios (the suites' mocked
# fetch responses).
SCENARIO_RAW = {}

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


# The item id from pi issue #1022: long, with + / = characters.
LONG_ITEM_ID = "t5nnb2qYMFWGSsr13fhCd1CaCu3t3qONEPuOudu4HSVEtA8YJSL6FAZUxvoOoD792VIJWl91g87EdqsCWp9krVsdBysQoDaf9lMCLb8BS4EYi4gQd5kBQBYLlgD71PYwvf+TbMD9J9/5OMD42oxSRj8H+vRf78/l2Xla33LWz4nOgsddBlbvabICRs8GHt5C9PK5keFtzyi3lsyVKNlfduK3iphsZqs4MLv4zyGJnvZo/+QzShyk5xnMSQX/f98+aEoNflEApCdEOXipipgeiNWnpFSHbcwmMkZoJhURNu+JEz3xCh1mrXeYoN5o+trLL3IXJacSsLYXDrYTipZZbJFRPAucgbnjYBC+/ZzJOfkwCs+Gkw7EoZR7ZQgJ8ma+9586n4tT4cI8DEhBSZsWMjrCt8dxKg=="


def first_tool_name(api, body):
    """The first declared tool, as a model names it back in its call."""
    tools = body.get('tools') or []
    if not tools:
        return 'tool'
    first = tools[0]
    if api == 'completions':
        return first['function']['name']
    if api == 'google':
        declarations = first.get('functionDeclarations') or first.get('function_declarations') or [{}]
        return declarations[0].get('name', 'tool')
    return first.get('name', 'tool')


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
    if kind == 'rid':
        return Reply(text('response id test'))
    if kind == 'imagetool':
        if index == 0:
            return Reply([tool(api, 1, first_tool_name(api, body), {})], stop='tool')
        return Reply(text('I see a red circle with a diameter of 100 pixels.'))
    if kind == 'interleaved':
        if index == 0:
            return Reply(thinking(api, 'I will multiply 328 by 29 with the calculator.') + [tool(api, 1, 'calculator', {'a': 328, 'b': 29, 'operation': 'multiply'})], stop='tool')
        return Reply(thinking(api, 'The tool says 9512 or 19024; 328 * 29 is 9512.') + text('328 * 29 = 9512.'))
    if kind == 'thinkingoff':
        return Reply(text(' '.join(['pong'] * 40)), usage=usage(input=40, output=41))
    if kind == 'toolname':
        return Reply([tool(api, 1, first_tool_name(api, body), {'task': 'buy milk'})], stop='tool')
    if kind == 'xhigh':
        effort = (body.get('reasoning') or {}).get('effort') or body.get('reasoning_effort')
        if effort == 'xhigh' and body.get('model') == 'gpt-5-mini':
            return Reply([], error=("Unsupported value: 'xhigh' is not supported with the 'gpt-5-mini' model. Supported values are: 'minimal', 'low', 'medium', and 'high'.", 'unsupported_value'))
        return Reply(thinking(api, 'Adding the two numbers.') + text('The sum is 100.'))
    if kind == 'toolid':
        if index == 0:
            return Reply([tool(api, 1, 'echo', {'message': 'hello world'}) + (LONG_ITEM_ID,)], stop='tool')
        return Reply(text('hi'))
    if kind == 'raw':
        return Reply([], raw=SCENARIO_RAW[scenario])
    if kind == 'zen':
        return Reply(text('Hello!'))
    raise AssertionError(kind)


# Executors
# ---------
def decoded(points):
    return ''.join(chr(int(p)) for p in points.split(',')) if points else ''


class Failed(AssertionError):
    pass


class Executor:
    def __init__(self, name, command, base, server=None):
        self.name, self.command, self.base, self.server = name, command, base, server
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
            elif line.startswith('M '):
                events.append(('model', json.loads(decoded(line[2:]))))
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


class CustomModel(Model):
    """A model literal written in a suite (upstream `Model` object)."""

    def __init__(self, custom, key='test-key'):
        self.custom = custom
        self.provider, self.id, self.override = custom['provider'], custom['id'], None
        self.api = custom['api']
        self.reasoning, self.input, self.cost_input, self.context_window = custom.get('reasoning', False), custom.get('input', ['text']), custom.get('cost', {}).get('input', 0), custom.get('contextWindow', 0)
        self.key = key


def case(model, run, context, options=None, entry='stream', **extra):
    if getattr(model, 'custom', None):
        extra = {'customModel': model.custom, **extra}
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
    'handleToolWithImageResult': lambda ex, model, run, options=None: toolImage(ex, model, run, options, False),
    'handleToolWithTextAndImageResult': lambda ex, model, run, options=None: toolImage(ex, model, run, options, True),
    'verifyToolResultImagesStayInFunctionCallOutput': lambda ex, model, run, options=None: verifyToolResultImages(ex, model, run, options),
    'expectResponseId': lambda ex, model, run, options=None: expectResponseId(ex, model, run, options),
}


# image-tool-result.test.ts, openai-responses-tool-result-images.test.ts
RED_CIRCLE = None


def red_circle():
    global RED_CIRCLE
    if RED_CIRCLE is None:
        RED_CIRCLE = base64.b64encode((UPSTREAM / 'packages/ai/test/data/red-circle.png').read_bytes()).decode()
    return RED_CIRCLE


def toolImage(ex, model, run, options, with_text):
    if 'image' not in model.input:
        return
    name = 'get_circle_with_description' if with_text else 'get_circle'
    description = 'Returns a circle image with a text description' if with_text else 'Returns a circle image for visualization'
    prompt = 'Use the get_circle_with_description tool and tell me what you learned. Also say what color the shape is.' if with_text else 'Call the get_circle tool to get an image, and describe what you see, shapes, colors, etc.'
    context = {'systemPrompt': 'You are a helpful assistant that uses tools when asked.', 'messages': [user(prompt)], 'tools': [{'name': name, 'description': description, 'parameters': {'type': 'object', 'properties': {}}}]}
    first = ex(case(model, run, context, options))['message']
    expect(first['stopReason'] == 'toolUse', first)
    call = next(block for block in first['content'] if block['type'] == 'toolCall')
    expect(call['name'] == name, call)
    content = ([{'type': 'text', 'text': 'This is a geometric shape with specific properties: it has a diameter of 100 pixels.'}] if with_text else []) + [{'type': 'image', 'data': red_circle(), 'mimeType': 'image/png'}]
    context['messages'] += [first, {'role': 'toolResult', 'toolCallId': call['id'], 'toolName': call['name'], 'content': content, 'isError': False, 'timestamp': 1}]
    second = ex(case(model, run, context, options))['message']
    expect(second['stopReason'] == 'stop' and not second.get('errorMessage'), second)
    lower = texts(second).lower()
    expect('red' in lower and 'circle' in lower and (not with_text or re.search('diameter|100|pixel', lower)), lower)


def verifyToolResultImages(ex, model, run, options):
    if 'image' not in model.input:
        return
    tool = {'name': 'get_circle_with_description', 'description': 'Returns a red circle image with a short text description.', 'parameters': {'type': 'object', 'properties': {}}}
    context = {'systemPrompt': 'You are a helpful assistant that always uses the provided tool when asked.', 'messages': [user('Call get_circle_with_description, then describe both the tool text and the image. Mention the color and shape.')], 'tools': [tool]}
    first = ex(case(model, run, context, options))['message']
    expect(first['stopReason'] == 'toolUse', first)
    call = next(block for block in first['content'] if block['type'] == 'toolCall')
    tool_text = 'A red circle with a diameter of 100 pixels.'
    context['messages'] += [first, {'role': 'toolResult', 'toolCallId': call['id'], 'toolName': call['name'], 'content': [{'type': 'text', 'text': tool_text}, {'type': 'image', 'data': red_circle(), 'mimeType': 'image/png'}], 'isError': False, 'timestamp': 1}]
    second = ex(case(model, run, context, options))['message']
    expect(second['stopReason'] == 'stop' and not second.get('errorMessage'), second)
    # onPayload's payload is the body the server received.
    payload = json.loads(ex.server.requests[f'{run}'][-1]['raw'])
    items = payload.get('input')
    expect(isinstance(items, list), payload)
    index = next(i for i, item in enumerate(items) if isinstance(item, dict) and item.get('type') == 'function_call_output')
    output = items[index]['output']
    expect(isinstance(output, list), output)
    text_item = next((item for item in output if item.get('type') == 'input_text'), None)
    image_item = next((item for item in output if item.get('type') == 'input_image'), None)
    expect(text_item and image_item and tool_text in text_item['text'] and image_item['image_url'].startswith('data:image/png;base64,'), output)
    expect(not [item for item in items[index + 1:] if isinstance(item, dict) and item.get('role') == 'user'], items[index + 1:])
    lower = texts(second).lower()
    expect('red' in lower and 'circle' in lower, lower)


# responseid.test.ts
def expectResponseId(ex, model, run, options):
    context = {'systemPrompt': 'You are a helpful assistant. Be concise.', 'messages': [user('Reply with exactly: response id test')]}
    response = ex(case(model, run, context, options))['message']
    expect(response['stopReason'] != 'error', response.get('errorMessage'))
    expect(isinstance(response.get('responseId'), str) and response['responseId'], response)


# interleaved-thinking.test.ts
CALCULATOR_TOOL = {'name': 'calculator', 'description': 'Perform basic arithmetic operations', 'parameters': {'type': 'object', 'required': ['a', 'b', 'operation'], 'properties': {'a': {'type': 'number', 'description': 'First number'}, 'b': {'type': 'number', 'description': 'Second number'}, 'operation': {'type': 'string', 'enum': ['add', 'subtract', 'multiply', 'divide'], 'description': 'The operation to perform.'}}}}


def interleaved(reasoning):
    def test(ex, model, run, options=None):
        context = {'systemPrompt': 'You are a helpful assistant that must use tools for arithmetic. Always think before every tool call, not just the first one. Do not answer with plain text when a tool call is required.',
                   'messages': [user('Use calculator to calculate 328 * 29. You must call the calculator tool exactly once. Provide the final answer based on the best guess given the tool result, even if it seems unreliable. Start by thinking about the steps you will take to solve the problem.')],
                   'tools': [CALCULATOR_TOOL]}
        first = ex(case(model, run, context, {'reasoning': reasoning}, entry='simple'))['message']
        expect(first['stopReason'] == 'toolUse', first.get('errorMessage'))
        expect(any(b['type'] == 'thinking' for b in first['content']) and any(b['type'] == 'toolCall' for b in first['content']), first)
        call = next(b for b in first['content'] if b['type'] == 'toolCall')
        a, b, op = call['arguments']['a'], call['arguments']['b'], call['arguments']['operation']
        answer = {'add': a + b, 'subtract': a - b, 'multiply': a * b, 'divide': a / b}[op]
        context['messages'] += [first, {'role': 'toolResult', 'toolCallId': call['id'], 'toolName': call['name'], 'content': [{'type': 'text', 'text': f'The answer is {answer} or {answer * 2}.'}], 'isError': False, 'timestamp': 1}]
        second = ex(case(model, run, context, {'reasoning': reasoning}, entry='simple'))['message']
        expect(second['stopReason'] == 'stop', second.get('errorMessage'))
        expect(any(b['type'] == 'thinking' for b in second['content']) and any(b['type'] == 'text' for b in second['content']), second)
    return test


# google-thinking-disable.test.ts
def thinkingDisabled(expression):
    expression = re.sub(r'\s+', ' ', expression or '')
    request = {}
    for key in ('maxTokens', 'temperature'):
        found = re.search(key + r': (\d+|undefined)', expression)
        if found:
            request[key] = None if found.group(1) == 'undefined' else int(found.group(1))
    min_pongs = int((re.search(r'minPongs: (\d+)', expression) or [None, 35])[1])
    max_output = re.search(r'maxOutputTokens: (\d+)', expression)

    def test(ex, model, run, options=None):
        merged = {'maxTokens': 160, 'temperature': 0, **request}
        merged = {key: value for key, value in merged.items() if value is not None}
        context = {'systemPrompt': 'You are a precise assistant. Follow the requested output format exactly.', 'messages': [user('Before replying, carefully solve 36863 * 5279 internally. Then reply with the word pong repeated exactly 40 times, separated by single spaces. Do not add any other text.')]}
        result = ex(case(model, run, context, merged, entry='simple'))
        response = result['message']
        expect(response['stopReason'] == 'stop', response.get('errorMessage'))
        thinking_events = [kind for kind, _ in result['events'] if kind.startswith('thinking_')]
        expect(not thinking_events and all(b['type'] != 'thinking' for b in response['content']), thinking_events)
        expect(len(re.findall(r'\bpong\b', texts(response).strip(), re.I)) >= min_pongs, texts(response))
        if max_output:
            expect(response['usage']['output'] < int(max_output.group(1)), response['usage'])
    return test


# xhigh.test.ts
def xhighSupported(ex, model, run, options=None):
    result = ex(case(model, run, {'messages': [user('What is 42 + 58? Think step by step.')]}, {'reasoningEffort': 'xhigh'}))
    response = result['message']
    expect(response['stopReason'] == 'stop', f"Error: {response.get('errorMessage')}")
    expect(any(b['type'] == 'text' for b in response['content']), response)
    expect(any(kind in ('thinking_start', 'thinking_delta') for kind, _ in result['events']) or any(b['type'] == 'thinking' for b in response['content']), result['events'])


def xhighRejected(ex, model, run, options=None):
    response = ex(case(model, run, {'messages': [user('What is 42 + 58? Think step by step.')]}, {'reasoningEffort': 'xhigh'}))['message']
    expect(response['stopReason'] == 'error' and 'xhigh' in (response.get('errorMessage') or ''), response)


# tool-call-id-normalization.test.ts
ECHO = {'name': 'echo', 'description': 'Echoes the message back', 'parameters': {'type': 'object', 'required': ['message'], 'properties': {'message': {'type': 'string', 'description': 'Message to echo back'}}}}
FAILING_TOOL_CALL_ID = 'call_pAYbIr76hXIjncD9UE4eGfnS|' + LONG_ITEM_ID


def liveHandoff(target_id, echoed):
    def test(ex, model, run, options=None):
        copilot = Model('github-copilot', 'gpt-5.5')
        target = Model(*target_id)
        SCENARIO_MODELS[run.split('~')[0] + 'g'] = copilot
        first_run = run.replace('~', 'g~', 1).replace(f'~{model.tag}~', f'~{copilot.tag}~')
        user_message = user(f"Use the echo tool to echo '{echoed}'")
        assistant = ex(case(copilot, first_run, {'systemPrompt': 'You are a helpful assistant. Use the echo tool when asked.', 'messages': [user_message], 'tools': [ECHO]}, entry='simple'))['message']
        expect(assistant['stopReason'] == 'toolUse', f"Copilot error: {assistant.get('errorMessage')}")
        call = next(b for b in assistant['content'] if b['type'] == 'toolCall')
        expect('|' in call['id'], call['id'])
        result = {'role': 'toolResult', 'toolCallId': call['id'], 'toolName': 'echo', 'content': [{'type': 'text', 'text': echoed}], 'isError': False, 'timestamp': 1}
        response = ex(case(target, run, {'systemPrompt': 'You are a helpful assistant.', 'messages': [user_message, assistant, result, user('Say hi')], 'tools': [ECHO]}, entry='simple'))['message']
        expect(response['stopReason'] != 'error' and response.get('errorMessage') is None, response.get('errorMessage'))
    return test


def prefilled(ex, model, run, options=None):
    assistant = {'role': 'assistant', 'content': [{'type': 'toolCall', 'id': FAILING_TOOL_CALL_ID, 'name': 'echo', 'arguments': {'message': 'hello'}}], 'api': 'openai-responses', 'provider': 'github-copilot', 'model': 'gpt-5.2-codex', 'usage': {'input': 100, 'output': 50, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 150, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}, 'stopReason': 'toolUse', 'timestamp': 1}
    result = {'role': 'toolResult', 'toolCallId': FAILING_TOOL_CALL_ID, 'toolName': 'echo', 'content': [{'type': 'text', 'text': 'hello'}], 'isError': False, 'timestamp': 1}
    response = ex(case(model, run, {'systemPrompt': 'You are a helpful assistant.', 'messages': [user("Use the echo tool to echo 'hello'"), assistant, result, user('Say hi')], 'tools': [ECHO]}, entry='simple'))['message']
    expect(response['stopReason'] != 'error', response.get('errorMessage'))


# anthropic-tool-name-normalization.test.ts
def toolName(tool, prompt, system, expected):
    def test(ex, model, run, options=None):
        result = ex(case(model, run, {'systemPrompt': system, 'messages': [user(prompt)], 'tools': [tool]}, {'apiKey': KEYS['anthropicOAuthToken']}))
        response = result['message']
        expect(response['stopReason'] == 'toolUse', f"Error: {response.get('errorMessage')}")
        call = next(b for b in response['content'] if b['type'] == 'toolCall')
        expect(call['name'] == expected, call['name'])
    return test


def string_tool(name, description, field, field_description):
    return {'name': name, 'description': description, 'parameters': {'type': 'object', 'required': [field], 'properties': {field: {'type': 'string', 'description': field_description}}}}


# zen.test.ts
def zenSmoke(ex, model, run, options=None):
    response = ex(case(model, run, {'messages': [user('Say hello.')]}))['message']
    expect(response['content'] and response['stopReason'] == 'stop', response)


# openai-responses-compat.test.ts (upstream mocks fetch and reads the request
# init; here the loopback server records the request)
def captured(ex, model, run, context, options, override=None, body='data: [DONE]\n\n'):
    SCENARIO_RAW[run.split('~')[0]] = body
    extra = {'modelOverride': override} if override else {}
    result = ex(dict(case(model, run, context, {'apiKey': 'test-key', **options}, entry='api'), **extra))
    request = ex.server.requests[run][-1]
    return result, request['headers'], json.loads(request['raw'])


SYS_HI = {'systemPrompt': 'sys', 'messages': [user('hi')]}


def capture_test(check, model_ids=('openai', 'gpt-5.4'), context=SYS_HI, options=None, override=None, body='data: [DONE]\n\n'):
    def test(ex, model, run, _options=None):
        result, headers, payload = captured(ex, Model(*model_ids), run, context, options or {}, override, body)
        check(result, headers, payload)
    return test


def affinity(session, request_id, x_session=None, key=None, no_session_field=False):
    def check(result, headers, payload):
        expect(headers.get('session_id') == session and headers.get('x-client-request-id') == request_id and headers.get('x-session-id') == x_session, headers)
        if no_session_field:
            expect('session_id' not in payload, payload)
        if key is not None:
            expect(payload.get('prompt_cache_key') == key, payload.get('prompt_cache_key'))
    return check


def responses_compat_tests():
    d = 'openai-responses-compat.test.ts > openai-responses provider defaults'
    rows = []

    def add(name, test, model_ids=('openai', 'gpt-5.4')):
        rows.append((f'{d} > {name}', test, Model(*model_ids), {}, 'raw'))
    add('omits reasoning when no reasoning is requested', capture_test(lambda r, h, p: expect('reasoning' not in p, p), ('github-copilot', 'gpt-5-mini')), ('github-copilot', 'gpt-5-mini'))
    ping = {'name': 'ping', 'description': 'Ping', 'parameters': {'type': 'object', 'required': ['value'], 'properties': {'value': {'type': 'string'}}}}
    add('forwards required tool choice', capture_test(lambda r, h, p: expect(p.get('tool_choice') == 'required' and p['tools'][0]['name'] == 'ping', p), context={'messages': [user('Do not call ping. Respond with text instead.')], 'tools': [ping]}, options={'toolChoice': 'required'}))
    tools = [{'name': 'ordinary', 'description': 'An ordinary tool', 'parameters': {'type': 'object', 'required': ['path'], 'properties': {'path': {'type': 'string'}, 'offset': {'type': 'number'}}}},
             {'name': 'constrained', 'description': 'A constrained tool', 'parameters': {'type': 'object', 'required': ['value'], 'properties': {'value': {'type': 'string'}}}, 'constrainedSampling': {'type': 'json_schema', 'strict': 'prefer'}}]
    add('sets strict mode explicitly for Cloudflare OpenAI Responses tools', capture_test(lambda r, h, p: expect([(t['name'], t.get('strict')) for t in p['tools']] == [('ordinary', False), ('constrained', True)], p['tools']), ('cloudflare-ai-gateway', 'gpt-5.6-sol'), context={'messages': [user('Use a tool.')], 'tools': tools}), ('cloudflare-ai-gateway', 'gpt-5.6-sol'))
    for id in ['gpt-5.1', 'gpt-5.2', 'gpt-5.3-codex', 'gpt-5.4', 'gpt-5.4-mini', 'gpt-5.4-nano', 'gpt-5.5', 'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-6-sol', 'gpt-6-luna']:
        add(f'sends none reasoning effort for OpenAI {id} when no reasoning is requested', capture_test(lambda r, h, p: expect((p.get('reasoning') or {}).get('effort') == 'none', p.get('reasoning')), ('openai', id)), ('openai', id))
    for id in ['gpt-5', 'gpt-5-mini', 'gpt-5-nano', 'gpt-5-pro', 'gpt-5.2-pro', 'gpt-5.4-pro', 'gpt-5.5-pro']:
        add(f'omits reasoning effort for OpenAI {id} when off is unsupported', capture_test(lambda r, h, p: expect('reasoning' not in p, p.get('reasoning')), ('openai', id)), ('openai', id))
    official = {'hostPath': True}
    proxy = lambda provider, compat=None: {'provider': provider, 'baseUrl': 'https://proxy.example.com/v1', 'hostPath': True, **({'compat': compat} if compat else {})}
    add('sets cache-affinity headers for official OpenAI Responses requests with a sessionId', capture_test(affinity('session-123', 'session-123'), options={'sessionId': 'session-123'}, override=official))
    add("clamps prompt_cache_key to OpenAI's 64-character limit", capture_test(lambda r, h, p: expect(p.get('prompt_cache_key') == 'x' * 64, p.get('prompt_cache_key')), options={'sessionId': 'x' * 67}, override=official))
    add('sets cache-affinity headers for proxy OpenAI Responses requests with a sessionId', capture_test(affinity('session-123', 'session-123'), options={'sessionId': 'session-123'}, override=proxy('opencode')))
    add('uses OpenRouter session-affinity header when configured', capture_test(affinity(None, None, 'session-proxy', 'session-proxy', True), options={'sessionId': 'session-proxy'}, override=proxy('proxy', {'sessionAffinityFormat': 'openrouter'})))
    add('auto-detects OpenRouter session-affinity header for OpenRouter Responses endpoints', capture_test(affinity(None, None, 'session-openrouter', 'session-openrouter', True), options={'sessionId': 'session-openrouter'}, override={'provider': 'openrouter', 'baseUrl': 'https://openrouter.ai/api/v1', 'hostPath': True}))
    add('uses OpenAI no-session format when configured', capture_test(affinity(None, 'session-proxy', None, 'session-proxy', True), options={'sessionId': 'session-proxy'}, override=proxy('proxy', {'sessionAffinityFormat': 'openai-nosession'})))
    add('uses OpenAI no-session format for OpenCode Responses models', capture_test(affinity(None, 'session-opencode', None, 'session-opencode'), ('opencode', 'gpt-5.4'), options={'sessionId': 'session-opencode'}, override={'hostPath': True}), ('opencode', 'gpt-5.4'))
    add('can omit OpenAI session_id header while preserving other affinity data', capture_test(affinity(None, 'session-123', key='session-123'), options={'sessionId': 'session-123'}, override=proxy('opencode', {'sessionAffinityFormat': 'openai-nosession'})))
    add('lets explicit headers override the default OpenAI cache-affinity headers', capture_test(lambda r, h, p: expect(h.get('session_id') == 'override-session' and h.get('x-client-request-id') == 'override-request', h), options={'sessionId': 'session-123', 'headers': {'session_id': 'override-session', 'x-client-request-id': 'override-request'}}, override=official))
    add('omits OpenAI cache-affinity headers when cacheRetention is none', capture_test(lambda r, h, p: expect(h.get('session_id') is None and h.get('x-client-request-id') is None, h), options={'cacheRetention': 'none', 'sessionId': 'session-123'}, override=official))
    for id, tier, multiplier in [('gpt-5.4', 'priority', 2), ('gpt-5.5', 'priority', 2.5), ('gpt-5.5', 'flex', 0.5)]:
        sse = 'data: ' + json.dumps({'type': 'response.completed', 'response': {'status': 'completed', 'service_tier': tier, 'usage': {'input_tokens': 100000, 'output_tokens': 100000, 'total_tokens': 200000, 'input_tokens_details': {'cached_tokens': 0}}}}) + '\n\n'

        def tier_check(result, headers, payload, multiplier=multiplier, id=id):
            cost = result['message']['usage']['cost']
            meta = META[('openai', id)]
            expect(abs(cost['input'] - meta['cost'] * multiplier * 0.1) < 1e-12 and abs(cost['output'] - meta['costOutput'] * multiplier * 0.1) < 1e-12 and abs(cost['total'] - (meta['cost'] + meta['costOutput']) * multiplier * 0.1) < 1e-12, cost)
        add(f'applies {id} {tier} service-tier cost multiplier', capture_test(tier_check, ('openai', id), options={'serviceTier': tier}, body=sse), ('openai', id))
    m = 'openai-responses-compat.test.ts > openai-responses max_output_tokens compat'
    rows.append((f'{m} > sends max_output_tokens by default', capture_test(lambda r, h, p: expect(p.get('max_output_tokens') == 1024, p), options={'maxTokens': 1024}), Model('openai', 'gpt-5.4'), {}, 'raw'))
    rows.append((f'{m} > omits max_output_tokens when supportsMaxOutputTokens is false', capture_test(lambda r, h, p: expect('max_output_tokens' not in p, p), options={'maxTokens': 1024}, override={'compatMerge': {'supportsMaxOutputTokens': False}}), Model('openai', 'gpt-5.4'), {}, 'raw'))
    return rows


ENV_KEYS = {}


def env_keys(ex, provider, env):
    """findEnvKeys/getEnvApiKey through the port's env-api-keys program (the
    same backend as the executor) or pinned pi-mono."""
    if ex.name == 'upstream':
        script = f"""
const {{ findEnvKeys, getEnvApiKey }} = await import({json.dumps(str(UPSTREAM / 'packages/ai/src/env-api-keys.ts'))});
const [p, env] = JSON.parse(process.argv[1]);
console.log(JSON.stringify([findEnvKeys(p, env) ?? null, getEnvApiKey(p, env) ?? null]));
"""
        return tuple(json.loads(subprocess.run(['bun', '-e', script, json.dumps([provider, env])], capture_output=True, text=True, check=True).stdout))
    command = ENV_KEYS[ex.name]
    line = subprocess.run(command + [provider + '|' + ';'.join(f'{k}={v}' for k, v in env.items())], cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()[-1]
    _, keys, key = line[2:].split('|')
    return (None if keys == 'undefined' else [k for k in keys.strip('[]').split(',') if k]), (None if key == 'undefined' else key)


def catalog(ex, provider):
    """The provider's built-in models, keyed by id (upstream getModels)."""
    result = ex({'catalog': provider})
    return {model['id']: model for kind, model in result['events'] if kind == 'model'}


# Model-catalog and payload suites. Upstream reads the payload through an
# onPayload hook that throws (so nothing is sent) or a mocked fetch; here the
# loopback server records the request the hook would have seen.
def matches(actual, expected):
    """vitest toMatchObject: objects match on the expected keys, recursively."""
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(key in actual and matches(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return isinstance(actual, list) and len(actual) == len(expected) and all(matches(a, e) for a, e in zip(actual, expected))
    return actual == expected


def payload_of(ex, model, run, context, options, entry='simple', override=None, body=None):
    SCENARIO_RAW[run.split('~')[0]] = body if body is not None else {'anthropic': '', 'completions': 'data: [DONE]\n\n'}.get(model.tag, 'data: [DONE]\n\n')
    extra = {'modelOverride': override} if override else {}
    result = ex(dict(case(model, run, context, options, entry=entry), **extra))
    requests = ex.server.requests.get(run, [])
    expect(requests, 'no request sent')
    return result, requests[-1]['headers'], json.loads(requests[-1]['raw'])


def test_hi(content='test'):
    return {'messages': [user(content, 0)]}


def model_facts(provider, check):
    def test(ex, model, run, options=None):
        check(catalog(ex, provider))
    return test


def payload_test(model_ids, options, check, context=None, entry='simple', override=None, body=None):
    def test(ex, model, run, _options=None):
        result, headers, payload = payload_of(ex, Model(*model_ids), run, context or test_hi(), options, entry, override, body)
        check(payload, headers, result)
    return test


def env_test(provider, env, keys, key):
    def test(ex, model, run, options=None):
        found = env_keys(ex, provider, env)
        expect(found[0] == keys and (key is None or found[1] == key), found)
    return test


def xai_tests():
    d = 'xai-responses.test.ts > xAI Responses provider'
    rows = []
    x = Model('xai', 'grok-4.5')

    def add(name, test, model=x):
        rows.append((f'{d} > {name}', test, model, {}, 'raw'))

    def retired(models):
        for id in ['grok-3', 'grok-3-fast', 'grok-4.20-0309-non-reasoning', 'grok-4.20-0309-reasoning', 'grok-build-0.1', 'grok-code-fast-1']:
            expect(id not in models, id)
    add('excludes retired and redundant models from the built-in catalog', model_facts('xai', retired))

    def routes(models):
        expect(all(m['api'] == 'openai-responses' for m in models.values()), [m['api'] for m in models.values()])
        expect(models['grok-4.5']['supportedThinkingLevels'] == ['low', 'medium', 'high'] and models['grok-4.6']['supportedThinkingLevels'] == ['low', 'medium', 'high', 'xhigh'] and models['grok-4.7']['supportedThinkingLevels'] == ['low', 'medium', 'high', 'xhigh'] and models['grok-4.3']['supportedThinkingLevels'] == ['off', 'low', 'medium', 'high'], {k: m['supportedThinkingLevels'] for k, m in models.items()})
    add('routes every built-in xAI model through Responses', model_facts('xai', routes))

    def grok47(models):
        m = models['grok-4.7']
        expect(m['api'] == 'openai-responses' and m['reasoning'] is True and m['input'] == ['text', 'image'] and m['contextWindow'] == 500000 and m['maxTokens'] == 500000, m)
        expect(m['cost'] == {'input': 2, 'output': 6, 'cacheRead': 0.5, 'cacheWrite': 0, 'tiers': [{'inputTokensAbove': 200000, 'input': 4, 'output': 12, 'cacheRead': 1, 'cacheWrite': 0}]}, m['cost'])
    add('includes Grok 4.7 capabilities and long-context pricing', model_facts('xai', grok47))
    completed = 'data: ' + json.dumps({'type': 'response.completed', 'sequence_number': 0, 'response': {'id': 'resp_xai_test', 'status': 'completed', 'output': [], 'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2, 'input_tokens_details': {'cached_tokens': 0}}}}) + '\n\ndata: [DONE]\n\n'
    host = {'hostPath': True}

    def bearer(p, h, r):
        expect(r['message']['stopReason'] == 'stop', r['message'].get('errorMessage'))
        expect(h.get('authorization') == 'Bearer xai-test-token' and h.get('session_id') == 'pi-session-123', h)
        expect(p.get('model') == 'grok-4.5' and p.get('store') is False and p.get('stream') is True and p.get('prompt_cache_key') == 'pi-session-123' and matches(p.get('reasoning'), {'effort': 'medium'}) and p.get('include') == ['reasoning.encrypted_content'] and 'prompt_cache_retention' not in p, p)
        expect(any(i.get('role') == 'developer' and i.get('content') == 'You are a careful coding assistant.' for i in p['input'] if isinstance(i, dict)), p['input'])
    careful = {'systemPrompt': 'You are a careful coding assistant.', 'messages': [user('hello')]}
    add('uses /responses with bearer auth and xAI-compatible request fields', payload_test(('xai', 'grok-4.5'), {'apiKey': 'xai-test-token', 'sessionId': 'pi-session-123', 'cacheRetention': 'long', 'reasoningEffort': 'medium'}, bearer, careful, 'stream', host, completed))
    add('requests encrypted reasoning without an effort override', payload_test(('xai', 'grok-4.5'), {'apiKey': 'xai-test-token'}, lambda p, h, r: expect(p.get('model') == 'grok-4.5' and p.get('store') is False and p.get('include') == ['reasoning.encrypted_content'] and 'reasoning' not in p, p), {'messages': [user('hello')]}, 'stream', host, completed))
    add('uses /responses for Grok 4.7 with xhigh effort and encrypted reasoning', payload_test(('xai', 'grok-4.7'), {'apiKey': 'xai-test-token', 'reasoningEffort': 'xhigh'}, lambda p, h, r: expect(p.get('model') == 'grok-4.7' and p.get('store') is False and p.get('stream') is True and matches(p.get('reasoning'), {'effort': 'xhigh'}) and p.get('include') == ['reasoning.encrypted_content'], p), careful, 'stream', host, completed), Model('xai', 'grok-4.7'))
    arch = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(os.uname().machine, os.uname().machine)
    agent = f'pi (linux {os.uname().release}; {arch})'
    ua = lambda expected: (lambda p, h, r: expect(r['message']['stopReason'] == 'stop' and h.get('user-agent') == expected, (h.get('user-agent'), r['message'].get('errorMessage'))))
    add("uses pi's User-Agent by default for Responses requests", payload_test(('xai', 'grok-4.5'), {'apiKey': 'test-token'}, ua(agent), {'messages': [user('hello')]}, 'api', {'provider': 'openai', 'baseUrl': 'https://api.openai.com/v1', 'hostPath': True}, completed))
    add('lets explicit headers override the default Responses User-Agent', payload_test(('xai', 'grok-4.5'), {'apiKey': 'xai-test-token', 'headers': {'User-Agent': 'custom-agent'}}, ua('custom-agent'), {'messages': [user('hello')]}, 'stream', host, completed))
    grok_custom = {'id': 'grok-custom', 'name': 'Grok Custom', 'api': 'openai-completions', 'provider': 'xai', 'baseUrl': 'https://api.x.ai/v1', 'reasoning': False, 'input': ['text'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}, 'contextWindow': 128000, 'maxTokens': 16384}
    chunks = [{'id': 'chatcmpl-ua', 'choices': [{'delta': {'content': 'ok'}, 'finish_reason': None, 'index': 0}]}, {'id': 'chatcmpl-ua', 'choices': [{'delta': {}, 'finish_reason': 'stop', 'index': 0}], 'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'prompt_tokens_details': {'cached_tokens': 0}, 'completion_tokens_details': {'reasoning_tokens': 0}}}]
    chunk_body = '\n\n'.join('data: ' + json.dumps(c) for c in chunks) + '\n\ndata: [DONE]\n\n'

    def completions_ua(expected, headers=None):
        def test(ex, model, run, options=None):
            result, h, p = payload_of(ex, CustomModel(grok_custom), run, {'messages': [user('hello')]}, {'apiKey': 'xai-test-token', **({'headers': headers} if headers else {})}, 'api', {'hostPath': True}, chunk_body)
            ua(expected)(p, h, result)
        return test
    add("uses pi's User-Agent by default for Completions requests", completions_ua(agent), CustomModel(grok_custom))
    add('lets explicit headers override the default Completions User-Agent', completions_ua('custom-agent', {'User-Agent': 'custom-agent'}), CustomModel(grok_custom))
    add('uses /responses for Grok 4.3', payload_test(('xai', 'grok-4.3'), {'apiKey': 'xai-test-token', 'reasoningEffort': 'low'}, lambda p, h, r: expect(p.get('model') == 'grok-4.3' and p.get('store') is False and p.get('include') == ['reasoning.encrypted_content'] and matches(p.get('reasoning'), {'effort': 'low'}), p), {'messages': [user('hello')]}, 'stream', host, completed), Model('xai', 'grok-4.3'))
    return rows


def baseten_tests():
    d = 'baseten-models.test.ts > Baseten models'
    rows = []

    def add(name, test, model=('baseten', 'zai-org/GLM-5.2')):
        rows.append((f'{d} > {name}', test, Model(*model), {}, 'raw'))
    add('keeps both GLM 5.2 endpoints text-only', model_facts('baseten', lambda m: expect(m['zai-org/GLM-5.2']['input'] == ['text'] and m['zai-org/GLM-5.2-Fast']['input'] == ['text'], m['zai-org/GLM-5.2'])))
    kimi = ('baseten', 'moonshotai/Kimi-K2.6')

    def kimi_toggle(ex, model, run, options=None):
        m = catalog(ex, 'baseten')['moonshotai/Kimi-K2.6']
        expect(m.get('thinkingLevelMap') == {'off': 'off', 'minimal': None, 'low': None, 'medium': None, 'high': 'high', 'xhigh': None, 'max': None}, m.get('thinkingLevelMap'))
        expect(matches(m.get('compat'), {'supportsReasoningEffort': False, 'thinkingFormat': 'baseten', 'chatTemplateArgs': {'enable_thinking': {'$var': 'thinking.enabled'}}}), m.get('compat'))
        expect(m['supportedThinkingLevels'] == ['off', 'high'], m['supportedThinkingLevels'])
        _, _, p = payload_of(ex, Model(*kimi), run, test_hi(), {'apiKey': 'test-baseten-key', 'reasoning': 'high'})
        expect(p.get('chat_template_args') == {'enable_thinking': True} and 'reasoning_effort' not in p, p)
    add('models Kimi K2.6 reasoning as an explicit off/on toggle', kimi_toggle, kimi)
    add('sends Baseten chat_template_args with reasoning effort', payload_test(('baseten', 'zai-org/GLM-5.2'), {'apiKey': 'test-baseten-key', 'reasoning': 'high'}, lambda p, h, r: expect(p.get('chat_template_args') == {'enable_thinking': True} and p.get('reasoning_effort') == 'high', p)))
    add('disables Baseten opt-in reasoning when thinking is off', payload_test(('baseten', 'zai-org/GLM-5.2'), {'apiKey': 'test-baseten-key'}, lambda p, h, r: expect(p.get('chat_template_args') == {'enable_thinking': False} and p.get('reasoning_effort') == 'none', p)))
    add('resolves BASETEN_API_KEY from the environment', env_test('baseten', {'BASETEN_API_KEY': 'test-baseten-key'}, ['BASETEN_API_KEY'], 'test-baseten-key'))
    return rows


QWEN_TEXT = ['MiniMax-M2.5', 'deepseek-v3.2', 'deepseek-v4-flash', 'deepseek-v4-pro', 'glm-5', 'glm-5.1', 'glm-5.2', 'kimi-k2.5', 'kimi-k2.6', 'kimi-k2.7-code', 'qwen3.6-flash', 'qwen3.6-plus', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.8-flash', 'qwen3.8-max']
QWEN_INDIVIDUAL = ['deepseek-v4-flash-0731', 'deepseek-v4-pro', 'deepseek-v4-pro-0813', 'glm-5.2', 'qwen3.6-flash', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.8-flash', 'qwen3.8-max']
QWEN_IMAGES = ['qwen-image-2.0', 'qwen-image-2.0-pro', 'wan2.7-image', 'wan2.7-image-pro']
QWEN_THINKING = ['deepseek-v3.2', 'deepseek-v4-flash', 'deepseek-v4-pro', 'glm-5', 'glm-5.1', 'glm-5.2', 'kimi-k2.5', 'kimi-k2.6', 'kimi-k2.7-code', 'qwen3.6-flash', 'qwen3.6-plus', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.8-flash', 'qwen3.8-max']


def qwen_tests():
    d = 'qwen-token-plan-models.test.ts > Qwen Token Plan models'
    rows = []

    def add(name, test, model=('qwen-token-plan-individual', 'glm-5.2')):
        rows.append((f'{d} > {name}', test, Model(*model), {}, 'raw'))
    add('exposes exactly the documented Individual text models', model_facts('qwen-token-plan-individual', lambda m: expect(sorted(m) == sorted(QWEN_INDIVIDUAL), sorted(m))))
    add('reuses the international Token Plan environment variable', env_test('qwen-token-plan-individual', {'QWEN_TOKEN_PLAN_API_KEY': 'test'}, ['QWEN_TOKEN_PLAN_API_KEY'], None))
    for provider in ('qwen-token-plan', 'qwen-token-plan-cn'):
        add(f'exposes all text models on {provider}', model_facts(provider, lambda m: expect(all(x in m for x in QWEN_TEXT), [x for x in QWEN_TEXT if x not in m])))
        add(f'omits image models from {provider}', model_facts(provider, lambda m: expect(not [x for x in QWEN_IMAGES if x in m], [x for x in QWEN_IMAGES if x in m])))
    thinking_cases = [(p, i) for p in ('qwen-token-plan', 'qwen-token-plan-cn') for i in QWEN_THINKING] + [('qwen-token-plan-individual', i) for i in QWEN_INDIVIDUAL]
    for provider, id in thinking_cases:
        add(f'sends Qwen thinking fields for {provider}/{id}', payload_test((provider, id), {'apiKey': 'test', 'reasoning': 'high'}, lambda p, h, r: expect(p.get('enable_thinking') is True and 'thinking' not in p, p), {'messages': [user('Hi')]}), (provider, id))
    effort_cases = [(p, i) for p in ('qwen-token-plan', 'qwen-token-plan-cn') for i in ['deepseek-v4-flash', 'deepseek-v4-pro', 'glm-5', 'glm-5.1', 'glm-5.2']] + [('qwen-token-plan-individual', i) for i in ['deepseek-v4-flash-0731', 'deepseek-v4-pro', 'deepseek-v4-pro-0813', 'glm-5.2']]
    q38 = [(p, i) for p in ('qwen-token-plan', 'qwen-token-plan-cn', 'qwen-token-plan-individual') for i in ['qwen3.8-flash', 'qwen3.8-max']]
    for provider, id in effort_cases:
        add(f'exposes Qwen reasoning_effort levels for {provider}/{id}', model_facts(provider, lambda m, id=id: expect(matches(m[id].get('thinkingLevelMap'), {'minimal': None, 'low': None, 'medium': None, 'high': 'high', 'xhigh': None, 'max': 'max'}), m[id].get('thinkingLevelMap'))), (provider, id))
    for provider, id in q38:
        add(f'exposes qwen3.8 reasoning_effort levels for {provider}/{id}', model_facts(provider, lambda m, id=id: expect(matches(m[id].get('thinkingLevelMap'), {'minimal': None, 'low': 'low', 'medium': 'medium', 'high': None, 'xhigh': 'xhigh', 'max': None}), m[id].get('thinkingLevelMap'))), (provider, id))
    for provider in ('qwen-token-plan', 'qwen-token-plan-cn', 'qwen-token-plan-individual'):
        add(f'omits retired qwen3.8-max-preview on {provider}', model_facts(provider, lambda m: expect('qwen3.8-max-preview' not in m, sorted(m))))
    for provider, id in effort_cases:
        add(f'sends Qwen reasoning_effort for {provider}/{id}', payload_test((provider, id), {'apiKey': 'test', 'reasoning': 'high'}, lambda p, h, r: expect(p.get('reasoning_effort') == 'high', p), {'messages': [user('Hi')]}), (provider, id))
    for provider, id in q38:
        add(f'sends qwen3.8 xhigh reasoning_effort for {provider}/{id}', payload_test((provider, id), {'apiKey': 'test', 'reasoning': 'xhigh'}, lambda p, h, r: expect(p.get('enable_thinking') is True and p.get('reasoning_effort') == 'xhigh' and 'thinking' not in p, p), {'messages': [user('Hi')]}), (provider, id))
    return rows


FIREWORKS_ANTHROPIC_COMPAT = {'allowEmptySignature': True, 'sendSessionAffinityHeaders': True, 'supportsEagerToolInputStreaming': False, 'supportsCacheControlOnTools': False, 'supportsLongCacheRetention': False}
LOOKUP = {'name': 'lookup', 'description': 'Look up a value', 'parameters': {'type': 'object', 'required': ['value'], 'properties': {'value': {'type': 'string'}}}}


def fireworks_model(compat=FIREWORKS_ANTHROPIC_COMPAT):
    return {'id': 'accounts/fireworks/models/kimi-k2p6', 'name': 'Kimi K2.6', 'api': 'anthropic-messages', 'provider': 'fireworks', 'baseUrl': 'http://127.0.0.1:0', 'reasoning': True, 'input': ['text', 'image'], 'cost': {'input': 0.95, 'output': 4, 'cacheRead': 0.16, 'cacheWrite': 0}, 'contextWindow': 262000, 'maxTokens': 262000, 'compat': compat}


def anthropic_model():
    return {'id': 'claude-opus-4-8', 'name': 'Claude Opus 4.8', 'api': 'anthropic-messages', 'provider': 'anthropic', 'baseUrl': 'http://127.0.0.1:0', 'reasoning': True, 'input': ['text'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}, 'contextWindow': 200000, 'maxTokens': 32000}


def openrouter_model(**extra):
    return {**anthropic_model(), 'id': 'anthropic/claude-opus-4.8', 'provider': 'openrouter', 'baseUrl': 'https://openrouter.ai/api', **extra}


def fireworks_tests():
    d = 'fireworks-models.test.ts > Fireworks models'
    rows = []

    def add(name, test, model=('fireworks', 'accounts/fireworks/models/kimi-k2p6')):
        rows.append((f'{d} > {name}', test, model if isinstance(model, Model) else Model(*model), {}, 'raw'))
    add('registers the default Kimi K2.6 model via Anthropic-compatible Messages API', model_facts('fireworks', lambda m: expect(matches(m['accounts/fireworks/models/kimi-k2p6'], {'api': 'anthropic-messages', 'provider': 'fireworks', 'baseUrl': 'https://api.fireworks.ai/inference', 'reasoning': True, 'input': ['text', 'image'], 'contextWindow': 262000, 'maxTokens': 262000}) and m['accounts/fireworks/models/kimi-k2p6']['cost'] == {'input': 0.95, 'output': 4, 'cacheRead': 0.16, 'cacheWrite': 0}, m['accounts/fireworks/models/kimi-k2p6'])))

    def glm_fast(m):
        base, fast = m['accounts/fireworks/models/glm-5p2'], m['accounts/fireworks/routers/glm-5p2-fast']
        expect(all(fast.get(k) == base.get(k) for k in ('api', 'baseUrl', 'compat', 'thinkingLevelMap')), (base, fast))
    add("aligns GLM 5.2 Fast with GLM 5.2's OpenAI-compatible config", model_facts('fireworks', glm_fast))
    for id in ['accounts/fireworks/models/glm-5p2', 'accounts/fireworks/routers/glm-5p2-fast']:
        add(f'omits unsupported long cache retention for {id}', payload_test(('fireworks', id), {'apiKey': 'test-fireworks-key', 'cacheRetention': 'long', 'sessionId': 'test-fireworks-session'}, lambda p, h, r: expect('prompt_cache_retention' not in p, p)), ('fireworks', id))
    k3_compat = {'supportsStore': False, 'supportsDeveloperRole': False, 'supportsStrictMode': True, 'requiresReasoningContentOnAssistantMessages': True, 'thinkingFormat': 'openai', 'supportsMidConvoSystemMessages': True, 'supportsMidConvoToolAdditions': True, 'sendSessionAffinityHeaders': True, 'supportsLongCacheRetention': False}
    k3_levels = {'off': None, 'minimal': None, 'low': 'low', 'medium': None, 'high': 'high', 'xhigh': None, 'max': 'max'}

    def kimi_k3(ex, model, run, options=None):
        m = catalog(ex, 'fireworks')
        for id in ('accounts/fireworks/models/kimi-k3', 'accounts/fireworks/routers/kimi-k3-fast'):
            expect(m[id]['api'] == 'openai-completions' and m[id]['baseUrl'] == 'https://api.fireworks.ai/inference/v1' and m[id].get('compat') == k3_compat and m[id].get('thinkingLevelMap') == k3_levels, m[id])
        _, _, p = payload_of(ex, Model('fireworks', 'accounts/fireworks/models/kimi-k3'), run, test_hi(), {'apiKey': 'test-fireworks-key', 'reasoning': 'max'})
        expect(p.get('reasoning_effort') == 'max', p)
    add('routes Kimi K3 through the OpenAI-compatible API with native effort controls', kimi_k3, ('fireworks', 'accounts/fireworks/models/kimi-k3'))
    for id, levels in [('accounts/fireworks/models/deepseek-v4-flash-0731', ['off', 'low', 'high', 'max']), ('accounts/fireworks/models/deepseek-v4-flash-vision-exp', ['off', 'low', 'high', 'max']), ('accounts/fireworks/models/deepseek-v4-pro-0813', ['off', 'low', 'high', 'max']), ('accounts/fireworks/models/qwen3p8-max', ['off', 'low', 'medium', 'xhigh']), ('accounts/fireworks/models/qwen3p8-2p4t-a95b', ['off', 'low', 'medium', 'xhigh'])]:
        def native_effort(ex, model, run, options=None, id=id, levels=levels):
            m = catalog(ex, 'fireworks')[id]
            expect(m['api'] == 'anthropic-messages' and (m.get('compat') or {}).get('forceAdaptiveThinking') is True and m['supportedThinkingLevels'] == levels, m)
            for n, level in enumerate(levels):
                sub = run.replace('~', f'x{n}~', 1)
                SCENARIO_MODELS[sub.split('~')[0]] = model
                _, _, p = payload_of(ex, Model('fireworks', id), sub, test_hi(), {'apiKey': 'test-fireworks-key', **({} if level == 'off' else {'reasoning': level})})
                expect(p.get('thinking') == ({'type': 'disabled'} if level == 'off' else {'type': 'adaptive', 'display': 'summarized'}) and p.get('output_config') == (None if level == 'off' else {'effort': level}), (level, p.get('thinking'), p.get('output_config')))
        add(f'sends native Messages effort levels for {id}', native_effort, ('fireworks', id))
    for id, levels in [('accounts/fireworks/models/glm-5p2', ['off', 'high', 'max']), ('accounts/fireworks/routers/glm-5p2-fast', ['off', 'high', 'max']), ('accounts/fireworks/models/kimi-k3', ['low', 'high', 'max']), ('accounts/fireworks/routers/kimi-k3-fast', ['low', 'high', 'max'])]:
        add(f'exposes distinct native effort levels for {id}', model_facts('fireworks', lambda m, id=id, levels=levels: expect(m[id]['supportedThinkingLevels'] == levels, m[id]['supportedThinkingLevels'])))

    def toggle_only(ex, model, run, options=None):
        m = catalog(ex, 'fireworks')['accounts/fireworks/models/kimi-k2p6']
        expect('forceAdaptiveThinking' not in (m.get('compat') or {}), m.get('compat'))
        _, _, p = payload_of(ex, Model('fireworks', 'accounts/fireworks/models/kimi-k2p6'), run, test_hi(), {'apiKey': 'test-fireworks-key', 'reasoning': 'high'})
        expect(p.get('thinking') == {'type': 'enabled', 'budget_tokens': 16384, 'display': 'summarized'} and 'output_config' not in p, p)
    add('keeps toggle-only Messages models without a verified fallback on budget-based thinking', toggle_only)
    add('resolves FIREWORKS_API_KEY from the environment', env_test('fireworks', {'FIREWORKS_API_KEY': 'test-fireworks-key'}, ['FIREWORKS_API_KEY'], 'test-fireworks-key'))
    add('sets Fireworks-specific compat for session affinity and unsupported tool fields', model_facts('fireworks', lambda m: expect(matches(m['accounts/fireworks/models/kimi-k2p6'].get('compat'), {'sendSessionAffinityHeaders': True, 'supportsEagerToolInputStreaming': False, 'supportsCacheControlOnTools': False, 'supportsLongCacheRetention': False, 'allowEmptySignature': True}), m['accounts/fireworks/models/kimi-k2p6'].get('compat'))))
    a = 'fireworks-models.test.ts > Anthropic-compatible session affinity and tool compat'
    context = {'messages': [user('Use the tool')], 'tools': [LOOKUP]}

    def anthropic_capture(custom, options, check):
        def test(ex, model, run, _options=None):
            _, h, p = payload_of(ex, CustomModel(custom), run, context, {'apiKey': 'test-key', 'cacheRetention': 'short', **options}, 'api', None, '')
            check(h, p)
        return test
    arow = lambda name, custom, options, check: rows.append((f'{a} > {name}', anthropic_capture(custom, options, check), CustomModel(custom), {}, 'raw'))
    arow('sends x-session-affinity header for Fireworks models', fireworks_model(), {'sessionId': 'fireworks-session-1'}, lambda h, p: expect(h.get('x-session-affinity') == 'fireworks-session-1', h))
    arow('omits x-session-affinity header for native Anthropic models', anthropic_model(), {'sessionId': 'anthropic-session-1'}, lambda h, p: expect('x-session-affinity' not in h, h))
    arow('omits x-session-affinity header when cacheRetention is none', fireworks_model(), {'sessionId': 'fireworks-session-2', 'cacheRetention': 'none'}, lambda h, p: expect('x-session-affinity' not in h, h))
    arow('sends only x-session-id for OpenRouter models', openrouter_model(), {'sessionId': 'openrouter-session-1'}, lambda h, p: expect(h.get('x-session-id') == 'openrouter-session-1' and 'x-session-affinity' not in h, h))
    arow('omits OpenRouter session headers when cacheRetention is none', openrouter_model(), {'sessionId': 'openrouter-session-2', 'cacheRetention': 'none'}, lambda h, p: expect('x-session-id' not in h and 'x-session-affinity' not in h, h))
    arow('allows OpenRouter session headers to be disabled', openrouter_model(compat={'sendSessionAffinityHeaders': False}), {'sessionId': 'openrouter-session-3'}, lambda h, p: expect('x-session-id' not in h, h))
    arow('omits cache_control on tools for Fireworks models', fireworks_model(), {}, lambda h, p: expect('cache_control' not in p['tools'][-1], p['tools']))
    arow('omits eager_input_streaming on tools for Fireworks models', fireworks_model(), {}, lambda h, p: expect(all('eager_input_streaming' not in t for t in p['tools']), p['tools']))
    arow('sends cache_control on tools for native Anthropic models', anthropic_model(), {}, lambda h, p: expect((p['tools'][-1].get('cache_control') or {}).get('type') == 'ephemeral', p['tools']))
    arow('sends eager_input_streaming on tools for native Anthropic models', anthropic_model(), {}, lambda h, p: expect(p['tools'][0].get('eager_input_streaming') is True, p['tools']))
    return rows


def custom_tests():
    """Suites whose tests are written inline rather than through a shared
    test function: (name, function, model, options, kind)."""
    rows = []
    x = 'xhigh.test.ts > xhigh reasoning'
    rows += [(f'{x} > gpt 5.5 (supports xhigh) > should work with openai-responses', xhighSupported, Model('openai', 'gpt-5.5'), {}, 'xhigh'),
             (f'{x} > gpt-5-mini (does not support xhigh) > should error with openai-responses when using xhigh', xhighRejected, Model('openai', 'gpt-5-mini'), {}, 'xhigh'),
             (f'{x} > gpt-5-mini (does not support xhigh) > should error with openai-completions when using xhigh', xhighRejected, Model('openai', 'gpt-5-mini', 'openai-completions'), {}, 'xhigh')]
    t = 'tool-call-id-normalization.test.ts > Tool Call ID Normalization'
    rows += [(f'{t} - Live Handoff > github-copilot -> openrouter should normalize pipe-separated IDs', liveHandoff(('openrouter', 'openai/gpt-5.5'), 'hello world'), Model('openrouter', 'openai/gpt-5.5'), {}, 'toolid'),
             (f'{t} - Live Handoff > github-copilot -> openai-codex should normalize pipe-separated IDs', liveHandoff(('openai-codex', 'gpt-5.5'), 'test message'), Model('openai-codex', 'gpt-5.5'), {}, 'toolid'),
             (f'{t} - Prefilled Context > openrouter should handle prefilled context with long pipe-separated IDs', prefilled, Model('openrouter', 'openai/gpt-5.5'), {}, 'toolid'),
             (f'{t} - Prefilled Context > openai-codex should handle prefilled context with long pipe-separated IDs', prefilled, Model('openai-codex', 'gpt-5.5'), {}, 'toolid')]
    a = 'anthropic-tool-name-normalization.test.ts > Anthropic OAuth tool name normalization'
    sonnet = Model('anthropic', 'claude-sonnet-4-6', key=KEYS['anthropicOAuthToken'])
    rows += [(f'{a} > should normalize user-defined tool matching CC name (todowrite -> TodoWrite -> todowrite)', toolName(string_tool('todowrite', 'Write a todo item', 'task', 'The task to add'), 'Add a todo: buy milk. Use the todowrite tool.', 'You are a helpful assistant. Use the todowrite tool when asked to add todos.', 'todowrite'), sonnet, {}, 'toolname'),
             (f"{a} > should handle pi's built-in tools (read, write, edit, bash)", toolName(string_tool('read', 'Read a file', 'path', 'File path'), 'Read the file /tmp/test.txt using the read tool.', 'You are a helpful assistant. Use the read tool to read files.', 'read'), sonnet, {}, 'toolname'),
             (f'{a} > should NOT map find to Glob - find is not a CC tool name', toolName(string_tool('find', 'Find files by pattern', 'pattern', 'Glob pattern'), 'Find all .ts files using the find tool.', 'You are a helpful assistant. Use the find tool to search for files.', 'find'), sonnet, {}, 'toolname'),
             (f"{a} > should handle custom tools that don't match any CC tool names", toolName(string_tool('my_custom_tool', 'A custom tool', 'input', 'Input value'), "Use my_custom_tool with input 'hello'.", 'You are a helpful assistant. Use my_custom_tool when asked.', 'my_custom_tool'), sonnet, {}, 'toolname')]
    rows += responses_compat_tests()
    rows += xai_tests()
    rows += baseten_tests()
    rows += qwen_tests()
    rows += fireworks_tests()
    for provider, label in (('opencode', 'OpenCode Zen'), ('opencode-go', 'OpenCode Go')):
        for id in META.get(('zen', provider), []):
            if (provider, id) in META and META[(provider, id)]['api'] in API_TAG:
                rows.append((f'zen.test.ts > OpenCode Models Smoke Test > {label}: {id}', zenSmoke, Model(provider, id), {}, 'zen'))
    return rows


# The upstream suites
# -------------------
# Each `it` of the pinned suites becomes one row: its describe and test names,
# its model (getModel, with the suites' `api` override) and the options its
# test function receives. Rows on other APIs, transports or local servers stay
# pending with the reason.
KINDS = {'testAbortSignal': 'abort', 'testImmediateAbort': 'immediate', 'testTokensOnAbort': 'tokens', 'testEmptyAssistantMessage': 'emptyassistant', 'basicTextGeneration': 'basic', 'handleToolCall': 'tool', 'handleStreaming': 'streaming', 'handleThinking': 'thinking', 'handleImage': 'image', 'multiTurn': 'multiturn', 'testToolCallWithoutResult': 'toolnores', 'testContextOverflow': 'overflow', 'testTotalTokensWithCache': 'total',
         'handleToolWithImageResult': 'imagetool', 'handleToolWithTextAndImageResult': 'imagetool', 'verifyToolResultImagesStayInFunctionCallOutput': 'imagetool', 'expectResponseId': 'rid', 'assertSecondToolCallWithInterleavedThinking': 'interleaved', 'expectThinkingDisabledE2E': 'thinkingoff'}
SUITES = {
    'stream.test.ts': ('Generate E2E Tests', ['basicTextGeneration', 'handleToolCall', 'handleStreaming', 'handleThinking', 'handleImage', 'multiTurn']),
    'abort.test.ts': ('AI Providers Abort Tests', ['testAbortSignal', 'testImmediateAbort', 'testAbortThenNewMessage']),
    'tokens.test.ts': ('Token Statistics on Abort', ['testTokensOnAbort']),
    'empty.test.ts': ('AI Providers Empty Message Tests', ['testEmptyMessage', 'testEmptyStringMessage', 'testWhitespaceOnlyMessage', 'testEmptyAssistantMessage']),
    'unicode-surrogate.test.ts': ('AI Providers Unicode Surrogate Pair Tests', ['testEmojiInToolResults', 'testRealWorldLinkedInData', 'testUnpairedHighSurrogate']),
    'tool-call-without-result.test.ts': ('Tool Call Without Result Tests', ['testToolCallWithoutResult']),
    'total-tokens.test.ts': ('totalTokens field', ['testTotalTokensWithCache']),
    'context-overflow.test.ts': ('Context overflow error handling', ['testContextOverflow']),
    'image-tool-result.test.ts': ('Tool Results with Images', ['handleToolWithImageResult', 'handleToolWithTextAndImageResult']),
    'openai-responses-tool-result-images.test.ts': ('Responses API tool result images', ['verifyToolResultImagesStayInFunctionCallOutput']),
    'responseid.test.ts': ('responseId E2E Tests', ['expectResponseId']),
    'interleaved-thinking.test.ts': (None, ['assertSecondToolCallWithInterleavedThinking']),
    'google-thinking-disable.test.ts': (None, ['expectThinkingDisabledE2E']),
}
BALANCED = r'(?:[^()]|\((?:[^()]|\([^()]*\))*\))*'


def upstream_rows():
    rows = []
    for file, (top, functions) in SUITES.items():
        source = (UPSTREAM / 'packages/ai/test' / file).read_text()
        for block in re.split(r'\ndescribe' if top is None else r'\n\tdescribe', source)[1:]:
            head = re.match(r'(?:\.skipIf\(' + BALANCED + r'\))?\(\s*"([^"]+)"', block)
            if not head:
                continue
            parts = re.split(r'\n\t+it(?=[.(])', block)
            title = head.group(1) if top is None else f'{top} > {head.group(1)}'
            shared_model = re.search(r'getModel\("([^"]+)", "([^"]+)"\)', parts[0])
            shared_api = re.search(r'api: "([a-z-]+)"|\.api = "([a-z-]+)"', parts[0])
            for part in parts[1:]:
                it = re.match(r'(\.skipIf\(' + BALANCED + r'\)|\.skip)?\(\s*"([^"]+)"', part)
                if not it:
                    continue
                model = re.search(r'getModel\("([^"]+)", "([^"]+)"\)', part) or shared_model
                api = re.search(r'api: "([a-z-]+)"|\.api = "([a-z-]+)"', part) or shared_api
                calls = re.findall(r'await (' + '|'.join(functions) + r')\((\w+|getModel\("[^"]+", "[^"]+"\))(?:, ((?:[^;])*?))?\);', part)
                inline = calls and re.match(r'getModel\("([^"]+)", "([^"]+)"\)', calls[0][1])
                if inline:
                    model = inline
                rows.append(dict(file=file, name=f'{file} > {title} > {it.group(2)}', describe=head.group(1), skipped=it.group(1) == '.skip', model=model.groups() if model else None, api=(api.group(1) or api.group(2)) if api else None, calls=calls, body=part, head=parts[0]))
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
    if function in ('assertSecondToolCallWithInterleavedThinking', 'expectThinkingDisabledE2E'):
        options, reason = ({}, None)
    else:
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
    if function == 'assertSecondToolCallWithInterleavedThinking':
        return interleaved(expression.strip().strip('"')), model, {}
    if function == 'expectThinkingDisabledE2E':
        return thinkingDisabled(row['calls'][0][2]), model, {}
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
    ids |= {('openai', id) for id in ['gpt-5.1', 'gpt-5.2', 'gpt-5.3-codex', 'gpt-5.4', 'gpt-5.4-mini', 'gpt-5.4-nano', 'gpt-5.5', 'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-6-sol', 'gpt-6-luna', 'gpt-5', 'gpt-5-nano', 'gpt-5-pro', 'gpt-5.2-pro', 'gpt-5.4-pro', 'gpt-5.5-pro']}
    ids |= {('github-copilot', 'gpt-5-mini'), ('cloudflare-ai-gateway', 'gpt-5.6-sol'), ('opencode', 'gpt-5.4')}
    ids |= {('github-copilot', 'gpt-5.5'), ('openrouter', 'openai/gpt-5.5'), ('openai', 'gpt-5.5'), ('openai', 'gpt-5-mini'), ('openai-codex', 'gpt-5.5'), ('anthropic', 'claude-sonnet-4-6')}
    script = f"""
const {{ getModel, getModels }} = await import({json.dumps(str(UPSTREAM / 'packages/ai/src/compat.ts'))});
const ids = JSON.parse(process.argv[1]);
const zen = Object.fromEntries(["opencode", "opencode-go"].map((p) => [p, getModels(p).map((x) => x.id)]));
for (const p of ["opencode", "opencode-go", "xai", "baseten", "fireworks", "qwen-token-plan", "qwen-token-plan-cn", "qwen-token-plan-individual"]) for (const x of getModels(p)) ids.push([p, x.id]);
const found = ids.map(([p, m]) => [p, m, getModel(p, m)]).filter(([, , x]) => x);
const gemini = getModels("github-copilot").find((candidate) => candidate.id.startsWith("gemini-"));
console.log(JSON.stringify({{ zen, models: found.map(([p, m, x]) => [p, m, {{ api: x.api, reasoning: x.reasoning, input: x.input, cost: x.cost.input, costOutput: x.cost.output, contextWindow: x.contextWindow }}]), gemini: gemini && [gemini.id, {{ api: gemini.api, reasoning: gemini.reasoning, input: gemini.input, cost: gemini.cost.input, contextWindow: gemini.contextWindow }}] }}));
"""
    result = json.loads(subprocess.run(['bun', '-e', script, json.dumps(sorted(ids))], capture_output=True, text=True, check=True).stdout)
    for provider, id, meta in result['models']:
        META[(provider, id)] = meta
    for provider, list in result['zen'].items():
        META[('zen', provider)] = list
    if result['gemini']:
        META['copilot-gemini'] = result['gemini'][0]
        META[('github-copilot', result['gemini'][0])] = result['gemini'][1]


def own_run(scenario, run):
    """The test's scenario, or a sub-scenario it derived (run + non-digit suffix)."""
    return scenario == run or (scenario.startswith(run) and not scenario[len(run)].isdigit())


def run_test(index, name, function, model, options, kind, server, backends, commands):
    """Runs one test through upstream and each backend; returns (status, lines)."""
    run = f'{kind}.{index}'
    SCENARIO_MODELS[run] = model
    reference = Executor('upstream', ['bun', 'tests/live_replay_reference.ts'], server.base, server)
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
        port = Executor(backend, commands[backend], server.base, server)
        try:
            function(port, model, f'{run}~{model.tag}~{backend}', options)
        except Failed as error:
            problems.append(f'{backend}: {error}')
        prefix = 'handoff' if kind.startswith('handoff') else run
        runs = sorted({key.rsplit('~', 1)[0] for key in list(server.requests) if key.endswith('~upstream') and (own_run(key.split('~')[0], run) or (kind.startswith('handoff') and key.startswith(kind + '.h')))})
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
    parser.add_argument('--env-prefix', default='build/env-api-keys', help='build of packages/ai/test/env-api-keys.bend (findEnvKeys rows)')
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
            tests.append((row['name'],) + planned + (KINDS.get(row['calls'][0][0]) or ('unicode' if row['file'].startswith('unicode') else 'empty'),))
    tests += custom_tests()
    handoff = Handoff(handoff_pairs())
    top = 'cross-provider-handoff.test.ts > Cross-Provider Handoff'
    first = handoff.pairs[0][1][0]
    tests += [(f'{top} > should have at least 2 fixtures to test handoffs', handoff.fixtures, first, None, 'handoffgen'), (f'{top} > should handle cross-provider handoffs for each target', handoff.targets, first, None, 'handoff')]
    if arguments.pending:
        for name, reason in pending:
            print(f'PENDING {name}: {reason}')
        return
    if not arguments.no_build:
        for entry, prefix in ((ENTRY, arguments.prefix), ('packages/ai/test/env-api-keys.bend', arguments.env_prefix)):
            if 'bun' in arguments.backends:
                subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', entry, '-o', prefix + '.js'], cwd=ROOT, check=True)
            if any(b.startswith('native') for b in arguments.backends):
                subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', entry, prefix], cwd=ROOT, check=True)
    commands = {'bun': ['bun', arguments.prefix + '.js'], 'native-1': [arguments.prefix, '--threads', '1'], 'native-4': [arguments.prefix, '--threads', '4']}
    env = arguments.env_prefix
    ENV_KEYS.update({'bun': ['bun', env + '.js'], 'native-1': [env, '--threads', '1'], 'native-4': [env, '--threads', '4']})
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
