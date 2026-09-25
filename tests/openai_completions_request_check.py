"""Chat Completions request side versus pinned upstream, with the upstream suites' named cases.

Each case runs the native provider (tests/openai-completions-request.bend) and
pinned pi-mono (tests/openai_completions_request_reference.ts) on the same
model, context and options. Request bodies must be byte-identical and the
session/auth/custom headers equal; each named case then applies the upstream
test's own assertions to the native result.
"""
import argparse
import copy
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = Path('/home/agent/code/pi-mono')
ENTRY = 'tests/openai-completions-request.bend'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/openai-completions-request')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--only', help='run cases whose suite/name contains this text')
arguments = parser.parse_args()

revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=UPSTREAM, text=True).strip()
assert revision.startswith('f07218c4d'), revision


def oracle(payload):
    return json.loads(subprocess.check_output(['bun', 'tests/openai_completions_request_reference.ts'], input=json.dumps(payload), text=True, cwd=ROOT))


# Fixtures
# --------

NOW = 1700000000000
ZERO_USAGE = dict(input=0, output=0, cacheRead=0, cacheWrite=0, totalTokens=0, cost=dict(input=0, output=0, cacheRead=0, cacheWrite=0, total=0))
COST = dict(input=0, output=0, cacheRead=0, cacheWrite=0)
CATALOG = {}


def catalog(provider, model_id):
    key = (provider, model_id)
    if key not in CATALOG:
        CATALOG[key] = oracle({'models': [list(key)]})[0]
        assert CATALOG[key] is not None, key
    return copy.deepcopy(CATALOG[key])


def definition(model):
    """A models.json-style definition plus the provider and base URL."""
    model = copy.deepcopy(model)
    provider = model.pop('provider')
    base = model.pop('baseUrl')
    model.pop('api', None)
    return dict(provider=provider, baseUrl=base, model=model)


def completions(catalog_provider, model_id, strip_compat=True, **overrides):
    """upstream `{ ...getModel(...), api: "openai-completions", ...overrides }`."""
    model = catalog(catalog_provider, model_id)
    if strip_compat:
        model.pop('compat', None)
    model.update(overrides)
    return definition(model)


def gpt4o_mini(**overrides):
    return completions('openai', 'gpt-4o-mini', **overrides)


LOCAL = dict(api='openai-completions', provider='local-vllm', baseUrl='http://localhost:8000/v1', reasoning=True, input=['text'], cost=COST, contextWindow=128000, maxTokens=8192)


def local(**fields):
    return definition({**LOCAL, **fields})


def from_catalog(provider, model_id):
    return dict(catalog=[provider, model_id])


def user(content, timestamp=NOW):
    return dict(role='user', content=content, timestamp=timestamp)


def assistant(content, provider='openai', model='gpt-4o-mini', stop='toolUse', api='openai-completions'):
    return dict(role='assistant', content=content, api=api, provider=provider, model=model, usage=ZERO_USAGE, stopReason=stop, timestamp=NOW)


def tool_call(call_id, name, arguments, **extra):
    return dict(type='toolCall', id=call_id, name=name, arguments=arguments, **extra)


def tool_result(call_id, name, content, timestamp=NOW):
    return dict(role='toolResult', toolCallId=call_id, toolName=name, content=content, isError=False, timestamp=timestamp)


def text(value):
    return dict(type='text', text=value)


def image(data='ZmFrZQ==', mime='image/png'):
    return dict(type='image', data=data, mimeType=mime)


def tool(name, description, properties, required=None, **extra):
    schema = dict(type='object', properties=properties, required=list(properties) if required is None else required)
    return dict(name=name, description=description, parameters=schema, **extra)


PING = tool('ping', 'Ping tool', {'ok': {'type': 'boolean'}})
READ = tool('read', 'Read a file', {'path': {'type': 'string'}})
STRICT_PING = tool('ping', 'Ping tool', {'required': {'type': 'string'}, 'optional': {'type': 'string'}}, required=['required'], constrainedSampling=dict(type='json_schema', strict='prefer'))


def case(entry, model, messages, options=None, **extra):
    value = dict(entry=entry, messages=messages, options=options or {})
    value.update(model)
    value.update(extra)
    return value


def simple(model, messages, options=None, **extra):
    return case('simple', model, messages, dict(apiKey='test', **(options or {})), **extra)


def streamed(model, messages, options=None, **extra):
    return case('stream', model, messages, dict(apiKey='test-key', **(options or {})), **extra)


def convert(model, messages, compat, **extra):
    fixture = copy.deepcopy(model)
    fixture['model']['compat'] = compat
    return case('convert', fixture, messages, compat=compat, **extra)


# Assertions on the native result
# -------------------------------

def body(result):
    assert 'body' in result, result
    return json.loads(result['body'])


def messages_of(result):
    assert 'messages' in result, result
    return json.loads(result['messages'])


def headers(result):
    return result['headers']


def absent(value, key):
    assert key not in value, (key, value)


def equal(actual, expected):
    assert actual == expected, (actual, expected)


def first_instruction(params):
    return next(message for message in params['messages'] if message['role'] in ('system', 'developer'))


def anthropic_markers(result):
    params = body(result)
    instruction = first_instruction(params)
    assert isinstance(instruction['content'], list), instruction
    equal(instruction['content'][0].get('cache_control'), {'type': 'ephemeral'})
    equal(len(params['tools']), 1)
    equal(params['tools'][0].get('cache_control'), {'type': 'ephemeral'})
    last = params['messages'][-1]
    equal(last['role'], 'user')
    assert isinstance(last['content'], list), last
    equal(last['content'][0].get('cache_control'), {'type': 'ephemeral'})


CASES = []


def test(suite, name, fixtures, check, compare=True, env=None):
    CASES.append(dict(suite=suite, name=name, fixtures=fixtures if isinstance(fixtures, list) else [fixtures], check=check, compare=compare, env=env))


# openai-completions-vllm-priority.test.ts
# ----------------------------------------

S = 'openai-completions-vllm-priority'
HI_SYS = dict(systemPrompt='sys')
test(S, 'sends compat.vllmPriority as the top-level priority request field', streamed(gpt4o_mini(compat=dict(vllmPriority=10)), [user('hi')], **HI_SYS), lambda r: equal(body(r[0]).get('priority'), 10))
test(S, 'omits priority when vllmPriority is not set', streamed(gpt4o_mini(), [user('hi')], **HI_SYS), lambda r: absent(body(r[0]), 'priority'))

# openai-completions-empty-tools.test.ts
# --------------------------------------

S = 'openai-completions-empty-tools'
test(S, 'omits tools field when context.tools is an empty array', simple(gpt4o_mini(), [user('hi')], tools=[]), lambda r: absent(body(r[0]), 'tools'))
test(S, 'omits tools field when context.tools is undefined', simple(gpt4o_mini(), [user('hi')]), lambda r: absent(body(r[0]), 'tools'))


def default_max(results):
    params = body(results[0])
    absent(params, 'max_tokens')
    equal(params['max_completion_tokens'], catalog('openai', 'gpt-4o-mini')['maxTokens'])


test(S, 'sends default maxTokens', simple(gpt4o_mini(), [user('hi')]), default_max)


def explicit_max(results):
    params = body(results[0])
    absent(params, 'max_tokens')
    equal(params['max_completion_tokens'], 1234)


test(S, 'sends explicit maxTokens', simple(gpt4o_mini(), [user('hi')], dict(maxTokens=1234)), explicit_max)


def clamped(results):
    params = body(results[0])
    absent(params, 'max_tokens')
    equal(params['max_completion_tokens'], 3904)


test(S, 'clamps default maxTokens to remaining context', simple(gpt4o_mini(contextWindow=10000, maxTokens=8000), [user('x' * 8000)]), clamped)
test(S, 'clamps explicit maxTokens to remaining context', simple(gpt4o_mini(contextWindow=10000, maxTokens=8000), [user('x' * 8000)], dict(maxTokens=7000)), clamped)

# The gateway endpoint and cf-aig-authorization come from the Cloudflare
# provider's auth (covered by tests/cloudflare_request_check.py); here the
# Completions request receives the materialized endpoint and those headers.
GATEWAY = 'https://gateway.ai.cloudflare.com/v1/account-id/gateway-id/compat'
CF_HEADERS = {'Authorization': None, 'cf-aig-authorization': 'Bearer cf-token'}


def gateway(model_id):
    model = catalog('cloudflare-ai-gateway', model_id)
    model['baseUrl'] = GATEWAY
    return definition(model)


def conservative(results):
    params = body(results[0])
    equal(params['messages'][0]['role'], 'system')
    equal(params.get('max_tokens'), 1234)
    absent(params, 'max_completion_tokens')
    absent(params, 'reasoning_effort')
    absent(params, 'store')
    equal(results[0]['url'], GATEWAY + '/chat/completions')
    absent(headers(results[0]), 'authorization')
    equal(headers(results[0])['cf-aig-authorization'], 'Bearer cf-token')


test(S, 'uses conservative OpenAI-compatible fields for Cloudflare AI Gateway /compat models', case('simple', gateway('workers-ai/@cf/moonshotai/kimi-k2.6'), [user('hi')], dict(maxTokens=1234, reasoning='high', headers=CF_HEADERS), systemPrompt='You are helpful.'), conservative)


def byok(results):
    equal(headers(results[0])['authorization'], 'Bearer upstream-token')
    equal(headers(results[0])['cf-aig-authorization'], 'Bearer cf-token')


test(S, 'preserves inline upstream Authorization for Cloudflare AI Gateway BYOK requests', case('simple', gateway('gpt-5.1'), [user('hi')], dict(headers={'Authorization': 'Bearer upstream-token', 'cf-aig-authorization': 'Bearer cf-token'})), byok)


def workers_affinity(results):
    for key in ('session_id', 'x-client-request-id', 'x-session-affinity'):
        equal(headers(results[0])[key], 'session-1')


test(S, 'sends session affinity headers for Workers AI through Cloudflare AI Gateway', case('simple', gateway('workers-ai/@cf/moonshotai/kimi-k2.6'), [user('hi')], dict(sessionId='session-1', headers=CF_HEADERS)), workers_affinity)
HISTORY = [user('use the tool'), assistant([tool_call('t1', 'noop', {})]), tool_result('t1', 'noop', [text('done')])]
test(S, 'still emits tools: [] for Anthropic/LiteLLM proxy when conversation has tool history', simple(gpt4o_mini(), HISTORY, tools=[]), lambda r: equal(body(r[0])['tools'], []))

# openai-completions-cache-control-format.test.ts
# -----------------------------------------------

S = 'openai-completions-cache-control-format'
CUSTOM_QWEN = local(id='custom-qwen', name='Custom Qwen', provider='openrouter', baseUrl='https://example.com/v1', maxTokens=32000, compat=dict(cacheControlFormat='anthropic'))
CACHE_CONTEXT = dict(systemPrompt='System prompt', tools=[READ])
test(S, 'applies Anthropic-style cache markers when model compat enables them', streamed(CUSTOM_QWEN, [user('Hello')], **CACHE_CONTEXT), lambda r: anthropic_markers(r[0]))
test(S, 'preserves Anthropic-style cache markers for OpenRouter Anthropic batch aliases', streamed(from_catalog('openrouter', 'anthropic/claude-fable-5.1:batch'), [user('Hello')], **CACHE_CONTEXT), lambda r: anthropic_markers(r[0]))
TOOL_TURN = [user('Read the file'), assistant([tool_call('call_1', 'read', {'path': 'README.md'})], provider='openrouter', model='anthropic/claude-fable-5.1:batch'), tool_result('call_1', 'read', [text('file contents')])]


def tool_marker(results):
    params = body(results[0])
    equal(next(message for message in params['messages'] if message['role'] == 'user')['content'], 'Read the file')
    last = params['messages'][-1]
    equal(last['role'], 'tool')
    assert isinstance(last['content'], list), last
    equal(last['content'][0].get('cache_control'), {'type': 'ephemeral'})


test(S, 'moves the conversation cache marker to a tool result', streamed(from_catalog('openrouter', 'anthropic/claude-fable-5.1:batch'), TOOL_TURN, **CACHE_CONTEXT), tool_marker)


def no_markers(results):
    params = body(results[0])
    assert not isinstance(first_instruction(params)['content'], list)
    absent(params['tools'][0], 'cache_control')
    assert isinstance(params['messages'][-1]['content'], str)


test(S, 'omits Anthropic-style cache markers when cacheRetention is none', streamed(CUSTOM_QWEN, [user('Hello')], dict(cacheRetention='none'), **CACHE_CONTEXT), no_markers)

# openai-completions-prompt-cache.test.ts
# ---------------------------------------

S = 'openai-completions-prompt-cache'


def cache_request(options=None, model=None, env=None):
    return streamed(model or gpt4o_mini(), [user('hi')], options, systemPrompt='sys')


def key_and_retention(key, retention):
    def check(results):
        params = body(results[0])
        equal(params.get('prompt_cache_key'), key)
        equal(params.get('prompt_cache_retention'), retention)
    return check


test(S, 'sets prompt_cache_key for direct OpenAI requests when caching is enabled', cache_request(dict(sessionId='session-123')), key_and_retention('session-123', None))
test(S, 'sets prompt_cache_retention to 24h for direct OpenAI requests when cacheRetention is long', cache_request(dict(cacheRetention='long', sessionId='session-456')), key_and_retention('session-456', '24h'))
test(S, "clamps prompt_cache_key to OpenAI's 64-character limit", cache_request(dict(sessionId='x' * 67)), key_and_retention('x' * 64, None))
test(S, 'omits prompt cache fields when cacheRetention is none', cache_request(dict(cacheRetention='none', sessionId='session-789')), key_and_retention(None, None))
test(S, 'omits prompt cache fields for non-OpenAI base URLs without compatible long retention', cache_request(dict(cacheRetention='long', sessionId='session-proxy'), gpt4o_mini(baseUrl='https://proxy.example.com/v1', compat=dict(supportsLongCacheRetention=False))), key_and_retention(None, None))
test(S, 'uses PI_CACHE_RETENTION for direct OpenAI requests', cache_request(dict(sessionId='session-env')), key_and_retention('session-env', '24h'), env={'PI_CACHE_RETENTION': 'long'})
PROXY_AFFINITY = gpt4o_mini(baseUrl='https://proxy.example.com/v1', compat=dict(sendSessionAffinityHeaders=True))


def affinity(expected, missing=()):
    def check(results):
        for key, value in expected.items():
            equal(headers(results[0]).get(key), value)
        for key in missing:
            absent(headers(results[0]), key)
    return check


test(S, 'sends known session-affinity headers when compat.sendSessionAffinityHeaders is enabled', cache_request(dict(sessionId='session-affinity'), PROXY_AFFINITY), affinity({'session_id': 'session-affinity', 'x-client-request-id': 'session-affinity', 'x-session-affinity': 'session-affinity'}))
for model_id in ('accounts/fireworks/models/glm-5p2', 'accounts/fireworks/routers/glm-5p2-fast'):
    test(S, f'sends Fireworks session affinity for {model_id}', cache_request(dict(sessionId='fireworks-session'), from_catalog('fireworks', model_id)), affinity({'x-session-affinity': 'fireworks-session'}))
test(S, 'sends Baseten session affinity for built-in catalog models', cache_request(dict(sessionId='baseten-catalog-session'), from_catalog('baseten', 'zai-org/GLM-5.2')), affinity({'x-session-affinity': 'baseten-catalog-session', 'x-client-request-id': 'baseten-catalog-session'}))


def nosession(results):
    params = body(results[0])
    absent(params, 'session_id')
    equal(params.get('prompt_cache_key'), 'session-nosession')
    affinity({'x-client-request-id': 'session-nosession', 'x-session-affinity': 'session-nosession'}, ('session_id', 'x-session-id'))(results)


test(S, 'uses OpenAI no-session format when configured', cache_request(dict(sessionId='session-nosession'), gpt4o_mini(compat=dict(sendSessionAffinityHeaders=True, sessionAffinityFormat='openai-nosession'))), nosession)


def openrouter_affinity(session):
    def check(results):
        params = body(results[0])
        absent(params, 'session_id')
        absent(params, 'prompt_cache_key')
        affinity({'x-session-id': session}, ('session_id', 'x-client-request-id', 'x-session-affinity'))(results)
    return check


test(S, 'uses OpenRouter session-affinity header when configured', cache_request(dict(sessionId='session-proxy'), gpt4o_mini(baseUrl='https://proxy.example.com/v1', compat=dict(sendSessionAffinityHeaders=True, sessionAffinityFormat='openrouter'))), openrouter_affinity('session-proxy'))
test(S, 'sends OpenRouter session-affinity header by default for built-in OpenRouter models', cache_request(dict(sessionId='session-openrouter'), from_catalog('openrouter', 'auto')), openrouter_affinity('session-openrouter'))


def openrouter_disabled(results):
    params = body(results[0])
    absent(params, 'session_id')
    absent(params, 'prompt_cache_key')
    absent(headers(results[0]), 'x-session-id')


test(S, 'omits OpenRouter session-affinity data when disabled', cache_request(dict(sessionId='session-openrouter'), gpt4o_mini(provider='openrouter', baseUrl='https://openrouter.ai/api/v1', compat=dict(sendSessionAffinityHeaders=False))), openrouter_disabled)
test(S, 'omits session-affinity headers when cacheRetention is none', cache_request(dict(cacheRetention='none', sessionId='session-affinity'), PROXY_AFFINITY), affinity({}, ('session_id', 'x-client-request-id', 'x-session-affinity')))
test(S, 'lets explicit headers override generated session-affinity headers', cache_request(dict(sessionId='session-affinity', headers={'session_id': 'override-session', 'x-client-request-id': 'override-request', 'x-session-affinity': 'override-affinity'}), PROXY_AFFINITY), affinity({'session_id': 'override-session', 'x-client-request-id': 'override-request', 'x-session-affinity': 'override-affinity'}))

# openai-completions-thinking-token-budget.test.ts
# ------------------------------------------------

S = 'openai-completions-thinking-token-budget'


def vllm(compat=None):
    return local(id='zai-org/glm-5.2', name='GLM 5.2 (local vLLM)', contextWindow=262144, maxTokens=16384, compat=compat if compat is not None else dict(thinkingFormat='zai', supportsThinkingTokenBudget=True))


def budget_request(model, **options):
    return simple(model, [user('Hi')], {key: value for key, value in options.items() if value is not None})


def field_is(name, value, missing=()):
    def check(results):
        for result in results:
            params = body(result)
            equal(params.get(name), value)
            for key in missing:
                absent(params, key)
    return check


test(S, 'sends the configured budget for the requested level', budget_request(vllm(), reasoning='medium', thinkingBudgets=dict(medium=4096)), field_is('thinking_token_budget', 4096))
test(S, 'omits the budget when neither the field nor the alias is set', budget_request(vllm(dict(thinkingFormat='zai')), reasoning='medium', thinkingBudgets=dict(medium=4096)), field_is('thinking_token_budget', None, ('thinking_budget', 'thinking_budget_tokens')))
test(S, 'omits the budget when thinking is off', budget_request(vllm(), thinkingBudgets=dict(high=8192)), field_is('thinking_token_budget', None))
test(S, 'clamps xhigh and max to the high budget', [budget_request(vllm(), reasoning='xhigh', thinkingBudgets=dict(high=8192)), budget_request(vllm(), reasoning='max', thinkingBudgets=dict(high=8192))], field_is('thinking_token_budget', 8192))
test(S, 'leaves room for the answer when the budget meets the response ceiling', budget_request(vllm(), reasoning='high'), field_is('thinking_token_budget', 16384 - 1024))
test(S, 'uses the caller max_tokens as the ceiling when it is lower than the model cap', budget_request(vllm(), reasoning='high', thinkingBudgets=dict(high=8192), maxTokens=4096), field_is('thinking_token_budget', 4096 - 1024))
for budget_field in ('thinking_budget', 'thinking_budget_tokens'):
    test(S, f'sends {budget_field} when thinkingTokenBudgetField is set', budget_request(vllm(dict(thinkingFormat='qwen', thinkingTokenBudgetField=budget_field)), reasoning='medium', thinkingBudgets=dict(medium=4096)), field_is(budget_field, 4096, ('thinking_token_budget',)))
test(S, 'lets thinkingTokenBudgetField win over the boolean alias', budget_request(vllm(dict(thinkingFormat='zai', supportsThinkingTokenBudget=True, thinkingTokenBudgetField='thinking_budget')), reasoning='medium', thinkingBudgets=dict(medium=4096)), field_is('thinking_budget', 4096, ('thinking_token_budget',)))
TEMPLATE_BUDGET = dict(thinkingFormat='chat-template', chatTemplateKwargs={'enable_thinking': {'$var': 'thinking.enabled'}, 'thinking_budget': {'$var': 'thinking.budget'}})
test(S, 'puts the clamped budget in chat_template_kwargs when $var is thinking.budget', budget_request(vllm(TEMPLATE_BUDGET), reasoning='high'), field_is('chat_template_kwargs', {'enable_thinking': True, 'thinking_budget': 16384 - 1024}, ('thinking_token_budget',)))
test(S, 'omits thinking.budget from chat_template_kwargs when thinking is off', budget_request(vllm(TEMPLATE_BUDGET)), field_is('chat_template_kwargs', {'enable_thinking': False}))

# openai-completions-tool-result-images.test.ts
# ---------------------------------------------

S = 'openai-completions-tool-result-images'
FULL_COMPAT = dict(supportsStore=True, supportsDeveloperRole=True, supportsReasoningEffort=True, supportsUsageInStreaming=True, supportsFinishReason=True, maxTokensField='max_completion_tokens', requiresToolResultName=False, requiresAssistantAfterToolResult=False, requiresThinkingAsText=False, requiresReasoningContentOnAssistantMessages=False, thinkingFormat='openai', openRouterRouting={}, vercelGatewayRouting={}, chatTemplateKwargs={}, chatTemplateArgs={}, zaiToolStream=False, supportsThinkingTokenBudget=False, supportsStrictMode=True, supportsOpenAIGrammarTools=False, supportsMidConvoSystemMessages=False, supportsMidConvoToolAdditions=False, cacheControlFormat='anthropic', sendSessionAffinityHeaders=False, sessionAffinityFormat='openai', supportsLongCacheRetention=True)
IMAGE_MODEL = gpt4o_mini(input=['text', 'image'])
test(S, 'omits empty text parts from user messages with images', convert(IMAGE_MODEL, [user([text(''), image()])], FULL_COMPAT), lambda r: equal(messages_of(r[0]), [{'role': 'user', 'content': [{'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,ZmFrZQ=='}}]}]))


def batched(results):
    converted = messages_of(results[0])
    equal([message['role'] for message in converted], ['user', 'assistant', 'tool', 'tool', 'user'])
    last = converted[-1]
    assert isinstance(last['content'], list), last
    equal(len([part for part in last['content'] if part.get('type') == 'image_url']), 2)


def read_image(call_id, timestamp):
    return tool_result(call_id, 'read', [text('Read image file [image/png]'), image()], timestamp)


test(S, 'batches tool-result images after consecutive tool results', convert(IMAGE_MODEL, [user('Read the images', NOW - 2), assistant([tool_call('tool-1', 'read', {'path': 'img-1.png'}), tool_call('tool-2', 'read', {'path': 'img-2.png'})]), read_image('tool-1', NOW + 1), read_image('tool-2', NOW + 2)], FULL_COMPAT), batched)


def empty_output(results):
    message = next(message for message in messages_of(results[0]) if message['role'] == 'tool')
    equal(message['content'], '(no tool output)')
    assert 'see attached image' not in message['content']


test(S, "uses '(no tool output)' placeholder for empty tool results without images", convert(IMAGE_MODEL, [user('Run the command', NOW - 1), assistant([tool_call('tool-1', 'bash', {'command': 'true'})]), tool_result('tool-1', 'bash', [text('')], NOW + 1)], FULL_COMPAT), empty_output)

# openai-completions-tool-choice.test.ts (request side)
# -----------------------------------------------------

S = 'openai-completions-tool-choice'


def forwarded(results):
    params = body(results[0])
    equal(params['tool_choice'], 'required')
    assert isinstance(params.get('tools'), list) and len(params['tools']) > 0, params


# SimpleStreamOptions.toolChoice is "auto" | "none"; upstream casts "required"
# into it. The native type cannot hold that value, so the SDK tool choice is
# passed where it is typed, OpenAICompletionsOptions.toolChoice (see notes).
test(S, 'forwards toolChoice from simple options to payload', case('stream', gpt4o_mini(), [user('Call ping with ok=true')], dict(apiKey='test', toolChoice='required'), tools=[PING]), forwarded)


def choice_without_tools(results):
    params = body(results[0])
    equal(params['tool_choice'], 'none')
    absent(params, 'tools')


test(S, 'includes toolChoice when no tools are provided', simple(gpt4o_mini(), [user('Summarize the conversation')], dict(toolChoice='none')), choice_without_tools)


def no_strict(results):
    function = body(results[0])['tools'][0]['function']
    assert function
    absent(function, 'strict')


test(S, 'omits strict when compat disables strict mode', simple(gpt4o_mini(compat=dict(supportsStrictMode=False)), [user('Call ping with ok=true')], tools=[PING]), no_strict)


def non_strict(results):
    function = body(results[0])['tools'][0]['function']
    absent(function, 'strict')
    equal(function['parameters']['required'], ['required'])


test(S, 'defaults unknown OpenAI-compatible endpoints to non-strict tools', simple(local(id='local-model', name='Local Model'), [user('Call ping')], tools=[STRICT_PING]), non_strict)


def strict(results):
    function = body(results[0])['tools'][0]['function']
    equal(function.get('strict'), True)
    equal(function['parameters']['required'], ['required', 'optional'])


test(S, 'preserves strict tools for capable built-in Chat Completions models', simple(from_catalog('groq', 'openai/gpt-oss-20b'), [user('Call ping')], tools=[STRICT_PING]), strict)
test(S, 'maps Groq Qwen reasoning levels to default reasoning_effort', simple(from_catalog('groq', 'qwen/qwen3.6-27b'), [user('Hi')], dict(reasoning='medium')), field_is('reasoning_effort', 'default'))
test(S, 'keeps normal reasoning_effort for groq models without compat mapping', simple(from_catalog('groq', 'openai/gpt-oss-20b'), [user('Hi')], dict(reasoning='medium')), field_is('reasoning_effort', 'medium'))
test(S, 'enables tool_stream for supported z.ai models with tools', simple(from_catalog('zai', 'glm-5.2'), [user('Call ping with ok=true')], tools=[PING]), field_is('tool_stream', True))


def zai_levels(results):
    for result, effort in zip(results, ('high', 'high', 'high', 'max')):
        params = body(result)
        equal(params['thinking'], {'type': 'enabled', 'clear_thinking': False})
        equal(params['reasoning_effort'], effort)


test(S, 'maps z.ai GLM-5.2 thinking levels to reasoning_effort', [simple(from_catalog('zai', 'glm-5.2'), [user('Hi')], dict(reasoning=level)) for level in ('low', 'medium', 'high', 'max')], zai_levels)
ZAI_REPLAY = [user('Read README.md'), assistant([dict(type='thinking', thinking='prior reasoning', thinkingSignature='reasoning_content'), tool_call('call_1', 'read', {'path': 'README.md'})], provider='zai', model='glm-5.2'), tool_result('call_1', 'read', [text('contents')]), user('Continue')]


def zai_replay(results):
    params = body(results[0])
    replayed = next(message for message in params['messages'] if message['role'] == 'assistant')
    equal(replayed.get('reasoning_content'), 'prior reasoning')
    equal(params['thinking'], {'type': 'enabled', 'clear_thinking': False})


test(S, 'preserves z.ai thinking when replaying reasoning_content', simple(from_catalog('zai', 'glm-5.2'), ZAI_REPLAY, dict(reasoning='high')), zai_replay)
test(S, 'omits z.ai GLM-5.2 reasoning_effort when thinking is off', simple(from_catalog('zai', 'glm-5.2'), [user('Hi')]), field_is('thinking', {'type': 'disabled'}, ('reasoning_effort',)))
ZAI_STREAM = catalog('zai', 'glm-5.2')
ZAI_STREAM['compat'] = {**ZAI_STREAM.get('compat', {}), 'zaiToolStream': True}
test(S, 'respects explicit z.ai tool_stream compat override', simple(definition(ZAI_STREAM), [user('Call ping with ok=true')], tools=[PING]), field_is('tool_stream', True))
test(S, 'omits tool_stream when no tools are provided', simple(from_catalog('zai', 'glm-5.2'), [user('Hi')]), field_is('tool_stream', None))


def first_role(role):
    def check(results):
        for result in results:
            equal(body(result)['messages'][0]['role'], role)
    return check


INSTRUCT = dict(systemPrompt='Follow instructions.')
test(S, 'uses system messages for non-OpenAI/Anthropic OpenRouter reasoning model instructions', simple(from_catalog('openrouter', 'deepseek/deepseek-v4-pro'), [user('Hi')], **INSTRUCT), first_role('system'))
test(S, 'keeps developer messages for OpenAI and Anthropic OpenRouter batch instructions', [simple(from_catalog('openrouter', model_id), [user('Hi')], **INSTRUCT) for model_id in ('openai/gpt-5.2-codex', 'anthropic/claude-fable-5.1:batch')], first_role('developer'))
test(S, 'keeps developer messages for OpenAI reasoning model instructions', simple(completions('openai', 'gpt-5.5'), [user('Hi')], **INSTRUCT), first_role('developer'))


def mimo_replay(results):
    params = body(results[0])
    replayed = next(message for message in params['messages'] if message['role'] == 'assistant')
    equal(replayed.get('reasoning_content'), '')
    equal(params['thinking'], {'type': 'enabled'})
    equal(params['reasoning_effort'], 'high')


test(S, 'replays Xiaomi MiMo assistant tool calls with empty reasoning_content when thinking is missing', simple(from_catalog('xiaomi', 'mimo-v2.5-pro'), [user('Read README.md'), assistant([tool_call('call_1', 'read', {'path': 'README.md'})], provider='xiaomi', model='mimo-v2.5-pro'), tool_result('call_1', 'read', [text('contents')])], dict(reasoning='high')), mimo_replay)
OPENCODE_GO = catalog('opencode-go', 'kimi-k2.6')
OPENCODE_COMPAT = {**OPENCODE_GO.get('compat', {}), **dict(supportsStore=False, supportsDeveloperRole=False, supportsReasoningEffort=True, supportsUsageInStreaming=True, supportsFinishReason=True, maxTokensField='max_completion_tokens', requiresToolResultName=False, requiresAssistantAfterToolResult=False, requiresThinkingAsText=False, requiresReasoningContentOnAssistantMessages=False, thinkingFormat='openai', openRouterRouting={}, vercelGatewayRouting={}, chatTemplateKwargs={}, chatTemplateArgs={}, zaiToolStream=False, supportsStrictMode=True, supportsOpenAIGrammarTools=False, sendSessionAffinityHeaders=False, sessionAffinityFormat='openai', supportsLongCacheRetention=True)}


def opencode_replay(results):
    first = messages_of(results[0])[0]
    equal(first['role'], 'assistant')
    equal(first.get('reasoning_content'), 'think')
    absent(first, 'reasoning')


test(S, 'replays OpenCode Go reasoning thinking blocks as reasoning_content', convert(completions('opencode-go', 'kimi-k2.6'), [assistant([dict(type='thinking', thinking='think', thinkingSignature='reasoning'), tool_call('call_1', 'read', {'path': 'README.md'})], provider='opencode-go', model='kimi-k2.6', stop='stop')], OPENCODE_COMPAT), opencode_replay)
test(S, 'sends thinking disabled for OpenCode Go Kimi K2.6 when thinking is off', simple(from_catalog('opencode-go', 'kimi-k2.6'), [user('Hi')]), field_is('thinking', {'type': 'disabled'}, ('reasoning_effort',)))
test(S, 'sends thinking enabled for OpenCode Go Kimi K2.6 when thinking is enabled', simple(from_catalog('opencode-go', 'kimi-k2.6'), [user('Hi')], dict(reasoning='high')), field_is('thinking', {'type': 'enabled'}, ('reasoning_effort',)))
test(S, 'omits disabled thinking for Moonshot Kimi K2.7 Code models', [simple(from_catalog(provider, 'kimi-k2.7-code'), [user('Hi')]) for provider in ('moonshotai', 'moonshotai-cn')], field_is('thinking', None, ('reasoning_effort',)))
test(S, 'keeps disabled thinking for Moonshot Kimi K2.6 when thinking is off', simple(from_catalog('moonshotai-cn', 'kimi-k2.6'), [user('Hi')]), field_is('thinking', {'type': 'disabled'}, ('reasoning_effort',)))
test(S, 'sends max_tokens for OpenCode completions models', [simple(from_catalog(provider, 'kimi-k2.6'), [user('Hi')], dict(maxTokens=123)) for provider in ('opencode-go', 'opencode')], field_is('max_tokens', 123, ('max_completion_tokens',)))
CUSTOM_DEEPSEEK = local(id='custom-deepseek-model', name='Custom DeepSeek Model', provider='custom-deepseek', baseUrl='https://api.deepseek.com')
UPPER_DEEPSEEK = local(id='custom-uppercase-deepseek-model', name='Custom Uppercase DeepSeek Model', provider='custom-deepseek', baseUrl='https://API.DeepSeek.COM')
test(S, 'sends max_tokens for built-in and custom DeepSeek API models', [simple(model, [user('Hi')], dict(maxTokens=123)) for model in (from_catalog('deepseek', 'deepseek-flash'), from_catalog('deepseek', 'deepseek-v4-pro'), CUSTOM_DEEPSEEK, UPPER_DEEPSEEK)], field_is('max_tokens', 123, ('max_completion_tokens',)))
test(S, 'sends max_tokens for Z.AI completions models', [simple(from_catalog('zai', model_id), [user('Hi')], dict(maxTokens=123)) for model_id in ('glm-5-turbo', 'glm-5.2')], field_is('max_tokens', 123, ('max_completion_tokens',)))
# Upstream's catalog gives this openai-responses model the Completions-only
# supportsReasoningEffort: false, and the test streams it through Completions.
# Native compat is typed by API, so the same model and compat are declared as
# a Completions model (see the inventory notes).
test(S, 'omits reasoning effort for OpenCode Grok Build', simple(completions('opencode', 'grok-build-0.1', strip_compat=False), [user('Hi')], dict(reasoning='high')), field_is('reasoning_effort', None))
test(S, 'uses OpenRouter reasoning object instead of reasoning_effort', simple(from_catalog('openrouter', 'deepseek/deepseek-r1'), [user('Hi')], dict(reasoning='high')), field_is('reasoning', {'effort': 'high'}, ('reasoning_effort',)))


def template_cases(expected):
    def check(results):
        for result, value in zip(results, expected):
            params = body(result)
            equal(params.get('chat_template_kwargs'), value)
            absent(params, 'thinking')
            absent(params, 'reasoning_effort')
    return check


BOOLEAN_TEMPLATE = local(id='deepseek-ai/DeepSeek-V3.1', name='DeepSeek V3.1 via vLLM', compat=dict(thinkingFormat='chat-template', supportsReasoningEffort=False, chatTemplateKwargs={'thinking': {'$var': 'thinking.enabled'}}))
test(S, 'uses configurable chat template boolean thinking kwargs', [simple(BOOLEAN_TEMPLATE, [user('Hi')], dict(reasoning='high')), simple(BOOLEAN_TEMPLATE, [user('Hi')])], template_cases([{'thinking': True}, {'thinking': False}]))
QWEN_TEMPLATE = local(id='Qwen/Qwen3-Coder', name='Qwen3 Coder via vLLM', compat=dict(thinkingFormat='qwen-chat-template', supportsReasoningEffort=False))
test(S, 'uses qwen chat template thinking kwargs', [simple(QWEN_TEMPLATE, [user('Hi')], dict(reasoning='high')), simple(QWEN_TEMPLATE, [user('Hi')])], template_cases([{'enable_thinking': True, 'preserve_thinking': True}, {'enable_thinking': False, 'preserve_thinking': True}]))
EFFORT_TEMPLATE = local(id='unsloth/gpt-oss-120b-GGUF', name='GPT OSS via vLLM', thinkingLevelMap={'xhigh': 'max'}, compat=dict(thinkingFormat='chat-template', supportsReasoningEffort=False, chatTemplateKwargs={'preserve_thinking': True, 'reasoning_effort': {'$var': 'thinking.effort', 'omitWhenOff': True}}))
test(S, 'uses configurable chat template effort kwargs with static kwargs', simple(EFFORT_TEMPLATE, [user('Hi')], dict(reasoning='xhigh')), field_is('chat_template_kwargs', {'preserve_thinking': True, 'reasoning_effort': 'max'}, ('reasoning_effort',)))


def ant_ling(results):
    metadata = results[0]['model']
    compat = metadata.get('compat', {})
    for key, value in dict(supportsStore=False, supportsDeveloperRole=False, supportsReasoningEffort=False, maxTokensField='max_tokens', thinkingFormat='ant-ling', supportsLongCacheRetention=False).items():
        equal(compat.get(key), value)
    equal(compat.get('supportsStrictMode'), True)
    absent(compat, 'requiresReasoningContentOnAssistantMessages')
    params = body(results[1])
    equal(params.get('max_tokens'), 123)
    absent(params, 'max_completion_tokens')
    equal(params['messages'][0]['role'], 'system')
    equal(params.get('reasoning'), {'effort': 'high'})
    for key in ('reasoning_effort', 'store', 'prompt_cache_key', 'prompt_cache_retention'):
        absent(params, key)


test(S, 'uses Ant Ling compatibility metadata', [dict(entry='metadata', catalog=['ant-ling', 'Ring-2.6-1T']), simple(from_catalog('ant-ling', 'Ring-2.6-1T'), [user('Hi')], dict(maxTokens=123, reasoning='high', cacheRetention='long', sessionId='ant-ling-session'), **INSTRUCT)], ant_ling)


def ant_ling_unmapped(results):
    for result in results:
        absent(body(result), 'reasoning')


test(S, 'omits Ant Ling reasoning for unmapped direct reasoning efforts and non-reasoning models', [case('stream', from_catalog('ant-ling', 'Ring-2.6-1T'), [user('Hi')], dict(apiKey='test', reasoningEffort='medium')), simple(from_catalog('ant-ling', 'Ling-2.6-flash'), [user('Hi')], dict(reasoning='high'))], ant_ling_unmapped)


# Catalog metadata cases: the native catalog entry must carry upstream's values.
def metadata_is(expected_by_model):
    def check(results):
        for result, expected in zip(results, expected_by_model):
            compat = result['model'].get('compat', {})
            for key, value in expected.get('compat', {}).items():
                if value is None:
                    absent(compat, key)
                else:
                    equal(compat.get(key), value)
            if 'thinkingLevelMap' in expected:
                equal(result['model'].get('thinkingLevelMap'), expected['thinkingLevelMap'])
    return check


def metadata(pairs):
    return [dict(entry='metadata', catalog=list(pair)) for pair in pairs]


test(S, 'stores z.ai tool_stream support in model compat metadata', metadata([('zai', 'glm-4.7'), ('zai', 'glm-5-turbo'), ('zai', 'glm-5.2')]), metadata_is([dict(compat=dict(zaiToolStream=True))] * 3))
GLM52_LEVELS = dict(off='none', minimal=None, low=None, medium=None, high='high', xhigh=None, max='max')
GLM53_LEVELS = dict(off=None, minimal=None, low='low', medium=None, high='high', xhigh=None, max='max')
test(S, 'stores z.ai effort metadata', metadata([('zai', 'glm-5.2'), ('zai', 'glm-5.2-highspeed'), ('zai', 'glm-5.3'), ('zai-coding-cn', 'glm-5.3')]), metadata_is([dict(compat=dict(supportsReasoningEffort=True), thinkingLevelMap=GLM52_LEVELS)] * 2 + [dict(compat=dict(supportsReasoningEffort=True), thinkingLevelMap=GLM53_LEVELS)] * 2))
test(S, 'stores OpenRouter Kimi K2.6 reasoning replay compat in built-in metadata', metadata([('openrouter', 'moonshotai/kimi-k2.6')]), metadata_is([dict(compat=dict(supportsDeveloperRole=False, requiresReasoningContentOnAssistantMessages=True))]))
XIAOMI = ('xiaomi', 'xiaomi-token-plan-cn', 'xiaomi-token-plan-ams', 'xiaomi-token-plan-sgp')
test(S, 'stores Xiaomi MiMo reasoning replay compat in built-in metadata', metadata([(provider, 'mimo-v2.5-pro') for provider in XIAOMI]), metadata_is([dict(compat=dict(requiresReasoningContentOnAssistantMessages=True, thinkingFormat='deepseek', maxTokensField=None, supportsDeveloperRole=None))] * 4))
QWEN_PLANS = ('qwen-token-plan', 'qwen-token-plan-cn', 'qwen-token-plan-individual')
test(S, 'stores Qwen Token Plan reasoning replay compat in built-in metadata', metadata([(provider, 'qwen3.7-max') for provider in QWEN_PLANS]), metadata_is([dict(compat=dict(thinkingFormat='qwen', requiresReasoningContentOnAssistantMessages=None, supportsDeveloperRole=False, supportsStore=False))] * 3))

# Supplementary differential cases
# --------------------------------
# Generated inputs beyond the named cases, compared byte-for-byte with upstream.

import itertools
import random

rng = random.Random(20260925)
SUPPLEMENTARY = []
FORMATS = ['openai', 'openrouter', 'deepseek', 'together', 'baseten', 'zai', 'qwen', 'chat-template', 'qwen-chat-template', 'string-thinking', 'ant-ling']
MAPPINGS = [None, {'off': None}, {'off': 'none', 'low': None, 'xhigh': 'max'}, {'low': 'lite', 'medium': None}]
TEMPLATE = {'flag': True, 'count': 3, 'label': 'x', 'nothing': None, 'enabled': {'$var': 'thinking.enabled'}, 'effort': {'$var': 'thinking.effort'}, 'quiet': {'$var': 'thinking.effort', 'omitWhenOff': True}, 'budget': {'$var': 'thinking.budget'}}
for fmt, reasoning, effort, mapping, supports in itertools.product(FORMATS, [True, False], [None, 'low', 'xhigh'], MAPPINGS, [True, False]):
    compat = dict(thinkingFormat=fmt, supportsReasoningEffort=supports, chatTemplateKwargs=TEMPLATE, chatTemplateArgs={'mode': {'$var': 'thinking.effort'}, 'thinking': {'$var': 'thinking.enabled', 'omitWhenOff': True}})
    if rng.random() < 0.3:
        compat['thinkingTokenBudgetField'] = rng.choice(['thinking_token_budget', 'thinking_budget', 'thinking_budget_tokens'])
    if rng.random() < 0.3:
        compat['supportsThinkingTokenBudget'] = True
    fields = dict(id='fmt-model', name='Format', reasoning=reasoning, contextWindow=128000, maxTokens=rng.choice([2000, 8192]))
    if mapping is not None:
        fields['thinkingLevelMap'] = mapping
    options = dict(apiKey='k')
    if effort:
        options['reasoningEffort'] = effort
    if rng.random() < 0.3:
        options['thinkingBudgets'] = dict(low=rng.choice([0, 512, 4096]), high=3000)
    if rng.random() < 0.3:
        options['maxTokens'] = rng.choice([0, 1500, 5000])
    SUPPLEMENTARY.append(case('stream', local(compat=compat, **fields), [user('hi')], options))

LONG_ID = 'call_' + 'a' * 30 + '|' + 'fc_' + 'b+/=' * 30
FOREIGN = [
    user('start'),
    assistant([dict(type='thinking', thinking='foreign thought', thinkingSignature='sig'), text('visible'), tool_call(LONG_ID, 'read', {'path': 'a'}), tool_call('call_x|', 'read', {'path': 'b'}), tool_call('c\U0001F600|i\U0001F600', 'read', {'path': 'c'})], provider='openai-codex', model='gpt-5', api='openai-responses'),
    tool_result(LONG_ID, 'read', [text('one')]),
    tool_result('call_x|', 'read', [text('two'), image()]),
    tool_result('c\U0001F600|i\U0001F600', 'read', [image()]),
    user('next'),
]
DETAILS = json.dumps([{'type': 'reasoning.summary', 'summary': 's', 'id': None, 'format': 'f', 'index': 0}, {'type': 'reasoning.encrypted', 'data': 'enc', 'id': 'e1'}, {'type': 'reasoning.text', 'text': 't', 'signature': None}])
LEGACY = json.dumps({'type': 'reasoning.encrypted', 'data': 'legacy', 'id': 'rs_1', 'format': 'openai-responses-v1'})
SAME = [
    user([text(''), text('look'), image()]),
    assistant([text('  '), dict(type='thinking', thinking='plan', thinkingSignature='reasoning_content'), dict(type='thinking', thinking=' '), text('answer'), tool_call('call_1', 'read', {'path': 'x'})], provider='local-vllm', model='conv-model'),
    tool_result('call_1', 'read', [text('')]),
    tool_result('call_1b', 'read', [text('orphan result')]),
    user('after tools'),
    assistant([dict(type='thinking', thinking='detailed', thinkingSignature=DETAILS), tool_call('call_2', 'read', {'path': 'y'}, thoughtSignature=LEGACY)], provider='local-vllm', model='conv-model'),
    tool_result('call_2', 'read', [text('found'), image()]),
    assistant([tool_call('call_3', 'read', {'n': 1.5, 'deep': [True, None, 'q']}, thoughtSignature=LEGACY)], provider='local-vllm', model='conv-model'),
    tool_result('call_3', 'read', [text('ok')]),
    assistant([dict(type='thinking', thinking='r', thinkingSignature='reasoning'), dict(type='thinking', thinking='s', thinkingSignature='bogus')], provider='local-vllm', model='conv-model'),
    assistant([], provider='local-vllm', model='conv-model', stop='aborted'),
    user([text('astral \U0001F600 text')]),
]
MID = [
    dict(role='system', content='initial', toolsAdded=[READ], timestamp=NOW),
    user('one'),
    dict(role='system', content='update', sections={'rules': 'be brief', 'old': None}, toolsAdded=[PING], timestamp=NOW + 1),
    user('two'),
    dict(role='system', content='', toolsRemoved=[{'name': 'ping'}], timestamp=NOW + 2),
    user('three'),
]
TRANSCRIPTS = [('foreign', FOREIGN), ('same', SAME), ('mid', MID)]
FLAGS = ['requiresToolResultName', 'requiresAssistantAfterToolResult', 'requiresThinkingAsText', 'requiresReasoningContentOnAssistantMessages', 'supportsMidConvoSystemMessages', 'supportsMidConvoToolAdditions', 'supportsDeveloperRole', 'supportsStrictMode']
for index in range(160):
    label, transcript = TRANSCRIPTS[index % len(TRANSCRIPTS)]
    compat = {flag: rng.random() < 0.5 for flag in FLAGS}
    if rng.random() < 0.5:
        compat['cacheControlFormat'] = 'anthropic'
    compat['supportsLongCacheRetention'] = rng.random() < 0.5
    compat['sendSessionAffinityHeaders'] = rng.random() < 0.5
    compat['sessionAffinityFormat'] = rng.choice(['openai', 'openai-nosession', 'openrouter'])
    provider = rng.choice(['local-vllm', 'openai', 'opencode-go', 'openrouter'])
    base = rng.choice(['http://localhost:8000/v1', 'https://api.openai.com/v1'])
    model = local(id='conv-model', name='Conv', provider=provider, baseUrl=base, reasoning=rng.random() < 0.7, input=rng.choice([['text'], ['text', 'image']]), compat=compat)
    options = dict(apiKey='k', sessionId=rng.choice(['s', 'x' * 70]), cacheRetention=rng.choice(['none', 'short', 'long']))
    extra = {}
    prompt = rng.choice([None, 'System prompt'])
    declared = rng.choice([None, [], [READ, PING]])
    if prompt is not None:
        extra['systemPrompt'] = prompt
    if declared is not None:
        extra['tools'] = declared
    SUPPLEMENTARY.append(case('stream', model, copy.deepcopy(transcript), options, **extra))

LARK = tool('grammar', 'Grammar tool', {'input': {'type': 'string'}}, constrainedSampling=dict(type='grammar', variants=dict(openai_lark='start: /[a-z]+/')))
REGEX = tool('pattern', 'Regex tool', {'value': {'type': 'string'}}, constrainedSampling=dict(type='grammar', variants=dict(openai_regex='[0-9]+')))
REQUIRED = tool('strictly', 'Strict tool', {'a': {'type': 'string'}, 'b': {'type': 'integer'}}, required=['a'], constrainedSampling=dict(type='json_schema', strict='require'))
GRAMMAR_REPLAY = [user('go'), assistant([tool_call('g1', 'grammar', {'input': 'abc'}), tool_call('g2', 'pattern', {'value': '42'})], provider='local-vllm', model='tools-model'), tool_result('g1', 'grammar', [text('done')]), tool_result('g2', 'pattern', [text('done')])]
for grammar, strict, tools in itertools.product([True, False], [True, False], [[LARK, REGEX], [LARK, REQUIRED], [REQUIRED], [PING, STRICT_PING]]):
    model = local(id='tools-model', name='Tools', compat=dict(supportsOpenAIGrammarTools=grammar, supportsStrictMode=strict, zaiToolStream=grammar))
    SUPPLEMENTARY.append(case('params', model, copy.deepcopy(GRAMMAR_REPLAY), dict(apiKey='k', toolChoice={'type': 'function', 'function': {'name': 'grammar'}}), tools=tools))

ROUTING = dict(allow_fallbacks=False, require_parameters=True, data_collection='deny', zdr=True, order=['a', 'b'], only=['a'], ignore=['c'], quantizations=['fp8'], sort='price', max_price=dict(prompt=1, completion='2'), preferred_min_throughput=dict(p50=10), preferred_max_latency=3)
for routing, vercel in itertools.product([None, {}, ROUTING, dict(sort=dict(by='latency', partition=None))], [None, {}, dict(only=['x']), dict(order=['y', 'z']), dict(only=[], order=['w'])]):
    compat = {}
    if routing is not None:
        compat['openRouterRouting'] = routing
    if vercel is not None:
        compat['vercelGatewayRouting'] = vercel
    SUPPLEMENTARY.append(case('stream', local(id='route', name='Route', reasoning=False, compat=compat), [user('hi')], dict(apiKey='k', temperature=0.7, samplingParams={'top_p': 0.5, 'temperature': 1, 'model': 'override', 'seed': 7}, headers={'X-Extra': 'v', 'session_id': None})))

# Running
# -------

HEADER_KEYS = {'session_id', 'x-client-request-id', 'x-session-affinity', 'x-session-id', 'authorization', 'cf-aig-authorization'}


def compared_headers(fixture):
    keys = set(HEADER_KEYS)
    keys |= {key.lower() for key in fixture.get('options', {}).get('headers', {}) or {}}
    keys |= {key.lower() for key in (fixture.get('model') or {}).get('headers', {}) or {}}
    return keys


def differential(fixture, expected, actual):
    entry = fixture['entry']
    if entry == 'metadata':
        return
    if entry == 'convert':
        assert actual == expected, ('convertMessages differs', actual, expected)
        return
    assert ('body' in actual) == ('body' in expected), ('request sent differs', actual, expected)
    if 'body' not in expected:
        return
    assert actual['body'] == expected['body'], ('body differs', actual['body'], expected['body'])
    if entry == 'params':
        return
    if 'url' in expected:
        assert actual.get('url') == expected['url'], (actual.get('url'), expected['url'])
    for key in compared_headers(fixture) if 'headers' in expected else ():
        assert actual['headers'].get(key) == expected['headers'].get(key), (key, actual['headers'], expected['headers'])


def encode(value):
    return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=True, separators=(',', ':')))


def decode(line):
    return json.loads(''.join(chr(int(part)) for part in line.split(',')))


def native(command, fixtures, env):
    run = subprocess.run(command + [encode(f) for f in fixtures], cwd=ROOT, capture_output=True, text=True, timeout=600, env={**os.environ, **(env or {})})
    assert run.returncode == 0, (run.stdout[-2000:], run.stderr[-4000:])
    results = [decode(line[2:]) for line in run.stdout.splitlines() if line.startswith('R ')]
    assert len(results) == len(fixtures), run.stdout[-2000:]
    return results


selected = [c for c in CASES if not arguments.only or arguments.only in c['suite'] + '/' + c['name']]
expected = {}
for env in {json.dumps(c['env'] or {}) for c in selected}:
    group = [c for c in selected if json.dumps(c['env'] or {}) == env]
    fixtures = [dict(f, processEnv=json.loads(env)) for c in group for f in c['fixtures']]
    results = iter(oracle({'cases': fixtures}))
    for c in group:
        expected[id(c)] = [next(results) for _ in c['fixtures']]

if not arguments.no_build:
    if any(name.startswith('native') for name in arguments.backends):
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable, 'scripts/run-rss-guarded.py', '--stats', arguments.prefix + '-build.json', '--', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)
    if 'bun' in arguments.backends:
        subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)

failures = 0
for backend in arguments.backends:
    command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
    for c in selected:
        try:
            actual = native(command, c['fixtures'], c['env'])
            for fixture, want, got in zip(c['fixtures'], expected[id(c)], actual):
                differential(fixture, want, got)
            c['check'](actual)
        except AssertionError as error:
            failures += 1
            print(f'FAIL {backend} {c["suite"]} > {c["name"]}: {str(error)[:3000]}')
    print(f'{backend}: {len(selected) - failures} of {len(selected)} named request cases match upstream')

if not arguments.only:
    supplementary_expected = oracle({'cases': SUPPLEMENTARY})
    for backend in arguments.backends:
        command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
        mismatches = 0
        for start in range(0, len(SUPPLEMENTARY), 24):
            chunk = SUPPLEMENTARY[start:start + 24]
            for offset, (fixture, want, got) in enumerate(zip(chunk, supplementary_expected[start:start + 24], native(command, chunk, None))):
                try:
                    differential(fixture, want, got)
                except AssertionError as error:
                    mismatches += 1
                    if mismatches <= 5:
                        print(f'FAIL {backend} supplementary #{start + offset}: {str(error)[:3000]}')
        failures += mismatches
        print(f'{backend}: {len(SUPPLEMENTARY) - mismatches} of {len(SUPPLEMENTARY)} supplementary requests match upstream')
sys.exit(1 if failures else 0)
