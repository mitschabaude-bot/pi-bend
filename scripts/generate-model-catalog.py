#!/usr/bin/env python3
"""Generate Bend model catalogs from pi-ai's generated provider data.

Usage: scripts/generate-model-catalog.py <data-dir> <provider-id>...

pi-mono generates `packages/ai/src/providers/data/<provider>.json` from
models.dev at build time (scripts/generate-models.ts); the files are not
checked in, but the published @earendil-works/pi-ai package ships them in
`dist/providers/data`. This script turns the same JSON into typed Bend catalogs under
packages/ai/src/providers/<provider>.models.bend. Numbers are emitted as exact
binary64 values: integers through U32.to_f64, decimals as correctly rounded
quotients of two integers. Every field present in the data is rendered;
unknown fields and values raise instead of being dropped.
"""
import json, pathlib, re, sys
from fractions import Fraction

ROOT = pathlib.Path(__file__).resolve().parents[1]
APIS = {
    'openai-responses': 'T.OpenAIResponsesApi{}',
    'openai-codex-responses': 'T.OpenAICodexResponsesApi{}',
    'openai-completions': 'T.OpenAICompletionsApi{}',
    'azure-openai-responses': 'T.AzureOpenAIResponsesApi{}',
    'anthropic-messages': 'T.AnthropicMessagesApi{}',
    'google-generative-ai': 'T.GoogleGenerativeAiApi{}',
    'google-vertex': 'T.GoogleVertexApi{}',
    'mistral-conversations': 'T.MistralConversationsApi{}',
    'bedrock-converse-stream': 'T.BedrockConverseStreamApi{}',
}
# Field order follows packages/ai/src/types.bend.
RESPONSES_COMPAT = ['supportsDeveloperRole', 'supportsMidConvoSystemMessages', 'sessionAffinityFormat', 'supportsLongCacheRetention', 'supportsStrictMode', 'supportsOpenAIGrammarTools', 'supportsAdditionalTools', 'supportsToolSearch', 'supportsExplicitPromptCacheMode', 'supportsMaxOutputTokens']
COMPLETIONS_COMPAT = [
    'supportsStore', 'supportsDeveloperRole', 'supportsReasoningEffort',
    'supportsUsageInStreaming', 'supportsFinishReason', 'maxTokensField',
    'requiresToolResultName', 'requiresAssistantAfterToolResult',
    'requiresThinkingAsText', 'requiresReasoningContentOnAssistantMessages',
    'thinkingFormat', 'chatTemplateKwargs', 'chatTemplateArgs',
    'openRouterRouting', 'vercelGatewayRouting', 'zaiToolStream',
    'thinkingTokenBudgetField', 'supportsThinkingTokenBudget',
    'supportsOpenAIGrammarTools', 'supportsMidConvoSystemMessages',
    'supportsMidConvoToolAdditions', 'supportsStrictMode', 'cacheControlFormat',
    'sendSessionAffinityHeaders', 'sessionAffinityFormat',
    'supportsLongCacheRetention', 'vllmPriority',
]
ANTHROPIC_COMPAT = [
    'supportsEagerToolInputStreaming', 'supportsLongCacheRetention',
    'sendSessionAffinityHeaders', 'sessionAffinityFormat',
    'supportsCacheControlOnTools', 'supportsTemperature', 'forceAdaptiveThinking',
    'allowEmptySignature', 'supportsStrictTools', 'supportsMidConvoEffort',
    'supportsMidConvoSystemMessages', 'supportsMidConvoToolChanges',
    'allowedFallbackModels',
]
# Catalog compat keys that are not part of the api's compat type. Upstream keeps
# them in the untyped compat object, where no code for that api reads them; the
# typed compat has no field for them (as provider-composer.bend compatFor).
FOREIGN_COMPAT = {'openai-responses': {'supportsReasoningEffort'}}
# String values map exactly as provider-composer.bend parses models.json compat.
AFFINITY = {'openai': 'T.OpenAISession{}', 'openai-nosession': 'T.OpenAINoSession{}', 'openrouter': 'T.OpenRouterSession{}'}
ANTHROPIC_AFFINITY = {'openrouter': 'T.AnthropicOpenRouterSession{}'}
MAX_TOKENS_FIELD = {'max_completion_tokens': 'T.MaxCompletionTokens{}', 'max_tokens': 'T.MaxTokens{}'}
THINKING_FORMAT = {
    'openai': 'T.OpenAIThinking{}', 'openrouter': 'T.OpenRouterThinking{}', 'deepseek': 'T.DeepSeekThinking{}',
    'together': 'T.TogetherThinking{}', 'baseten': 'T.BasetenThinking{}', 'zai': 'T.ZaiThinking{}',
    'qwen': 'T.QwenThinking{}', 'chat-template': 'T.ChatTemplateThinking{}',
    'qwen-chat-template': 'T.QwenChatTemplateThinking{}', 'string-thinking': 'T.StringThinking{}',
    'ant-ling': 'T.AntLingThinking{}',
}
THINKING_TOKEN_BUDGET_FIELD = {'thinking_token_budget': 'T.ThinkingTokenBudget{}', 'thinking_budget': 'T.ThinkingBudgetField{}', 'thinking_budget_tokens': 'T.ThinkingBudgetTokens{}'}
CACHE_CONTROL_FORMAT = {'anthropic': 'T.AnthropicCacheControl{}'}
THINKING_VARIABLE = {'thinking.enabled': 'T.ThinkingEnabled{}', 'thinking.effort': 'T.ThinkingEffort{}', 'thinking.budget': 'T.ThinkingBudget{}'}
DATA_COLLECTION = {'deny': 'T.DenyCollection{}', 'allow': 'T.AllowCollection{}'}
INPUTS = {'text': 'T.InputText{}', 'image': 'T.InputImage{}'}
LEVELS = {'minimal': 'T.Minimal{}', 'low': 'T.Low{}', 'medium': 'T.Medium{}', 'high': 'T.High{}', 'xhigh': 'T.XHigh{}', 'max': 'T.Max{}'}

def text(value):
    if not isinstance(value, str):
        raise ValueError(f'expected a string: {value!r}')
    return json.dumps(value, ensure_ascii=False)

def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(value)
    if value < 0:
        # OpenRouter prices its router pseudo-models at -1000000.
        return f'F64.neg({number(-value)})'
    if float(value) == int(value) and int(value) < 2**32:
        return f'U32.to_f64({int(value)})'
    fraction = Fraction(repr(float(value)))
    if fraction.numerator >= 2**32 or fraction.denominator >= 2**32:
        raise ValueError(f'number out of catalog range: {value}')
    return f'F64.div(U32.to_f64({fraction.numerator}), U32.to_f64({fraction.denominator}))'

def maybe(value, render):
    return 'None{}' if value is None else f'Some{{{render(value)}}}'

def boolean(value):
    if not isinstance(value, bool):
        raise ValueError(f'expected a boolean: {value!r}')
    return 'True{}' if value else 'False{}'

def enum(table, what):
    def render(value):
        if value not in table:
            raise ValueError(f'unknown {what}: {value!r}')
        return table[value]
    return render

def cost(value):
    exact_keys(value, ['input', 'output', 'cacheRead', 'cacheWrite', 'tiers'], 'cost')
    tiers = value.get('tiers')
    rendered_tiers = None if tiers is None else 'List.reverse(&2, T.ModelCostTier, ' + reduce_list([cost_tier(t) for t in tiers]) + ')'
    return 'T.ModelCost{' + ', '.join(number(value[k]) for k in ('input', 'output', 'cacheRead', 'cacheWrite')) + ', ' + maybe(rendered_tiers, lambda t: t) + '}'

def cost_tier(value):
    keys = ['input', 'output', 'cacheRead', 'cacheWrite', 'inputTokensAbove']
    exact_keys(value, keys, 'cost tier')
    return 'T.ModelCostTier{' + ', '.join(number(value[k]) for k in keys) + '}'

def reduce_list(items):
    # Build lists as reversed cons chains to keep every line short.
    out = 'Nil{}'
    for item in items:
        out = f'{item} <> {out}'
    return out

def thinking_map(value):
    entries = []
    for level, mapped in value.items():
        rendered_level = 'T.Off{}' if level == 'off' else f'T.Thinking{{{enum(LEVELS, "thinking level")(level)}}}'
        rendered_value = 'Some{T.NullValue{}}' if mapped is None else f'Some{{T.PresentValue{{{text(mapped)}}}}}'
        entries.append(f'T.ThinkingLevelMapping{{{rendered_level}, {rendered_value}}}')
    return 'T.ThinkingLevelMap{' + ordered(entries) + '}'

def ordered(items):
    return '[' + ', '.join(items) + ']' if items else 'Nil{}'

def strings(value):
    if not isinstance(value, list):
        raise ValueError(f'expected a string list: {value!r}')
    return ordered([text(item) for item in value])

def record(value, render):
    if not isinstance(value, dict):
        raise ValueError(f'expected an object: {value!r}')
    return 'Record.Record{' + ordered([f'Record.Property{{{text(k)}, {render(v)}}}' for k, v in value.items()]) + '}'

# chatTemplateKwargs/chatTemplateArgs values: JSON scalars or a
# {"$var": ..., "omitWhenOff"?: ...} thinking variable.
def template_value(value):
    if value is None:
        return 'T.TemplateNull{}'
    if isinstance(value, bool):
        return f'T.TemplateBoolean{{{boolean(value)}}}'
    if isinstance(value, str):
        return f'T.TemplateString{{{text(value)}}}'
    if isinstance(value, (int, float)):
        return f'T.TemplateNumber{{{number(value)}}}'
    exact_keys(value, ['$var', 'omitWhenOff'], 'template variable')
    return f'T.TemplateVariable{{{enum(THINKING_VARIABLE, "template variable")(value["$var"])}, {maybe(value.get("omitWhenOff"), boolean)}}}'

def routing_sort(value):
    if isinstance(value, str):
        return f'T.SortByName{{{text(value)}}}'
    exact_keys(value, ['by', 'partition'], 'routing sort')
    partition = value.get('partition', ...)
    rendered_partition = 'None{}' if partition is ... else ('Some{T.NullValue{}}' if partition is None else f'Some{{T.PresentValue{{{text(partition)}}}}}')
    return f'T.SortByOptions{{{maybe(value.get("by"), text)}, {rendered_partition}}}'

def price(value):
    return f'T.StringPrice{{{text(value)}}}' if isinstance(value, str) else f'T.NumericPrice{{{number(value)}}}'

def max_price(value):
    keys = ['prompt', 'completion', 'image', 'audio', 'request']
    exact_keys(value, keys, 'routing max price')
    return 'T.RoutingMaxPrice{' + ', '.join(maybe(value.get(k), price) for k in keys) + '}'

def preference(value):
    if isinstance(value, dict):
        keys = ['p50', 'p75', 'p90', 'p99']
        exact_keys(value, keys, 'routing percentiles')
        return 'T.PercentilePreference{T.RoutingPercentiles{' + ', '.join(maybe(value.get(k), number) for k in keys) + '}}'
    return f'T.OverallPreference{{{number(value)}}}'

def open_router_routing(value):
    renderers = {
        'allow_fallbacks': boolean, 'require_parameters': boolean,
        'data_collection': enum(DATA_COLLECTION, 'data collection'), 'zdr': boolean,
        'enforce_distillable_text': boolean, 'order': strings, 'only': strings,
        'ignore': strings, 'quantizations': strings, 'sort': routing_sort,
        'max_price': max_price, 'preferred_min_throughput': preference,
        'preferred_max_latency': preference,
    }
    return 'T.OpenRouterRouting{' + fields(value, renderers, 'OpenRouter routing') + '}'

def vercel_gateway_routing(value):
    return 'T.VercelGatewayRouting{' + fields(value, {'only': strings, 'order': strings}, 'Vercel gateway routing') + '}'

def fallback_model(value):
    exact_keys(value, ['provider', 'model', 'cost'], 'allowed fallback model')
    return f'T.AnthropicAllowedFallbackModel{{{text(value["provider"])}, {text(value["model"])}, {cost(value["cost"])}}}'

# Renders the optional fields of `value` in the order of `renderers`.
def fields(value, renderers, what, ignored=()):
    exact_keys(value, list(renderers) + list(ignored), what)
    return ', '.join(maybe(value.get(key), render) for key, render in renderers.items())

COMPAT_RENDERERS = {
    'openai-completions': ('T.OpenAICompletionsCompat', {
        key: boolean for key in COMPLETIONS_COMPAT
    } | {
        'maxTokensField': enum(MAX_TOKENS_FIELD, 'maxTokensField'),
        'thinkingFormat': enum(THINKING_FORMAT, 'thinkingFormat'),
        'chatTemplateKwargs': lambda v: record(v, template_value),
        'chatTemplateArgs': lambda v: record(v, template_value),
        'openRouterRouting': open_router_routing,
        'vercelGatewayRouting': vercel_gateway_routing,
        'thinkingTokenBudgetField': enum(THINKING_TOKEN_BUDGET_FIELD, 'thinkingTokenBudgetField'),
        'cacheControlFormat': enum(CACHE_CONTROL_FORMAT, 'cacheControlFormat'),
        'sessionAffinityFormat': enum(AFFINITY, 'sessionAffinityFormat'),
        'vllmPriority': number,
    }),
    'openai-responses': ('T.OpenAIResponsesCompat', {key: boolean for key in RESPONSES_COMPAT} | {'sessionAffinityFormat': enum(AFFINITY, 'sessionAffinityFormat')}),
    'anthropic-messages': ('T.AnthropicMessagesCompat', {key: boolean for key in ANTHROPIC_COMPAT} | {
        'sessionAffinityFormat': enum(ANTHROPIC_AFFINITY, 'sessionAffinityFormat'),
        'allowedFallbackModels': lambda v: ordered([fallback_model(m) for m in v]),
    }),
}
COMPAT_RENDERERS['bedrock-converse-stream'] = ('T.BedrockCompat', {'supportsStrictMode': boolean})
COMPAT_RENDERERS['mistral-conversations'] = ('T.MistralConversationsCompat', {'supportsMidConvoSystemMessages': boolean})
COMPAT_RENDERERS['openai-codex-responses'] = COMPAT_RENDERERS['openai-responses']
COMPAT_RENDERERS['azure-openai-responses'] = COMPAT_RENDERERS['openai-responses']

def compat(api, value):
    if api not in COMPAT_RENDERERS:
        raise ValueError(f'unsupported compat for {api}')
    constructor, renderers = COMPAT_RENDERERS[api]
    return constructor + '{' + fields(value, renderers, f'{api} compat', FOREIGN_COMPAT.get(api, ())) + '}'

def model(api, value):
    known = {'id', 'name', 'api', 'provider', 'baseUrl', 'reasoning', 'thinkingLevelMap', 'input', 'inputLimits', 'cost', 'promptCache', 'contextWindow', 'maxTokens', 'compat', 'headers'}
    unknown = set(value) - known
    if unknown:
        raise ValueError(f'unknown model fields for {value["id"]}: {sorted(unknown)}')
    if value['api'] != api:
        raise ValueError(f'{value["id"]}: api {value["api"]} listed under {api}')
    inputs = ordered([enum(INPUTS, 'input')(k) for k in value['input']])
    headers = maybe(value.get('headers'), lambda h: record(h, text))
    return 'T.Model{' + ', '.join([
        text(value['id']), text(value['name']), APIS[api], text(value['provider']), text(value['baseUrl']),
        boolean(value['reasoning']), maybe(value.get('thinkingLevelMap'), thinking_map), inputs, maybe(value.get('inputLimits'), input_limits), cost(value['cost']), maybe(value.get('promptCache'), prompt_cache),
        number(value['contextWindow']), number(value['maxTokens']), 'None{}', headers, maybe(value.get('compat'), lambda c: compat(api, c)),
    ]) + '}'

def exact_keys(value, keys, what):
    if not isinstance(value, dict):
        raise ValueError(f'expected {what} object: {value!r}')
    unknown = set(value) - set(keys)
    if unknown:
        raise ValueError(f'unknown {what} fields: {sorted(unknown)}')

def resize(value):
    keys = ['maxWidth', 'maxHeight', 'maxBytes', 'jpegQuality']
    exact_keys(value, keys, 'image resize')
    return 'T.ModelImageResizeOptions{' + ', '.join(maybe(value.get(k), number) for k in keys) + '}'

def image_limits(value):
    exact_keys(value, ['resize', 'maxPerMessage', 'maxPerRequest'], 'image input limit')
    return 'T.ModelImageInputLimits{' + ', '.join([maybe(value.get('resize'), resize), maybe(value.get('maxPerMessage'), number), maybe(value.get('maxPerRequest'), number)]) + '}'

def input_limits(value):
    exact_keys(value, ['maxRequestBytes', 'images'], 'input limit')
    return 'T.ModelInputLimits{' + ', '.join([maybe(value.get('maxRequestBytes'), number), maybe(value.get('images'), image_limits)]) + '}'

def prompt_cache(value):
    keys = ['short', 'long']
    exact_keys(value, keys, 'prompt cache')
    return 'T.ModelPromptCache{' + ', '.join(maybe(value.get(k), number) for k in keys) + '}'

def identifier(model_id):
    return 'model_' + re.sub(r'[^A-Za-z0-9]', '_', model_id)

def generate(data_dir, provider):
    groups = json.loads((data_dir / f'{provider}.json').read_text())
    lines = ['import Base', 'import ../types.bend as T', 'import ../../../runtime/src/record.bend as Record', '',
             f'# Generated by scripts/generate-model-catalog.py from pi-ai provider data ({provider}.json).', '# Do not edit manually.', '']
    names = []
    for api, models in groups.items():
        if api not in APIS:
            raise ValueError(f'{provider}: unsupported api {api}')
        for model_id, value in models.items():
            if value['id'] != model_id or value['provider'] != provider:
                raise ValueError(f'{provider}: entry {model_id} is {value["provider"]}/{value["id"]}')
            name = identifier(model_id)
            if name in names:
                raise ValueError(f'{provider}: identifier collision {name}')
            names.append(name)
            lines.append(f'def {name}() -> T.Model<T.JsonValue>: {model(api, value)}')
            lines.append('')
    constant = provider.upper().replace('-', '_') + '_MODELS'
    lines.append(f'def {constant}() -> List<&2, T.Model<T.JsonValue>>: ' + ordered([f'{n}()' for n in names]))
    lines.append('')
    target = ROOT / 'packages/ai/src/providers' / f'{provider}.models.bend'
    target.write_text('\n'.join(lines))
    print(f'{target}: {len(names)} models')

if __name__ == '__main__':
    data_dir = pathlib.Path(sys.argv[1])
    for provider in sys.argv[2:]:
        generate(data_dir, provider)
