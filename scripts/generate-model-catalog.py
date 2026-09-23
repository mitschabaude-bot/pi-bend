#!/usr/bin/env python3
"""Generate Bend model catalogs from pi-ai's generated provider data.

Usage: scripts/generate-model-catalog.py <data-dir> <provider-id>...

pi-mono generates `packages/ai/src/providers/data/<provider>.json` from
models.dev at build time (scripts/generate-models.ts); the files are not
checked in, but the published @earendil-works/pi-ai package ships them in
`dist/providers/data`. This script turns the same JSON into typed Bend catalogs under
packages/ai/src/providers/<provider>.models.bend. Numbers are emitted as exact
binary64 values: integers through U32.to_f64, decimals as correctly rounded
quotients of two integers.
"""
import json, pathlib, re, sys
from fractions import Fraction

ROOT = pathlib.Path(__file__).resolve().parents[1]
APIS = {
    'openai-responses': 'T.OpenAIResponsesApi{}',
    'openai-codex-responses': 'T.OpenAICodexResponsesApi{}',
    'openai-completions': 'T.OpenAICompletionsApi{}',
    'azure-openai-responses': 'T.AzureOpenAIResponsesApi{}',
    'google-generative-ai': 'T.GoogleGenerativeAiApi{}',
}
RESPONSES_COMPAT = ['supportsDeveloperRole', 'supportsMidConvoSystemMessages', 'sessionAffinityFormat', 'supportsLongCacheRetention', 'supportsStrictMode', 'supportsOpenAIGrammarTools', 'supportsAdditionalTools', 'supportsToolSearch', 'supportsExplicitPromptCacheMode', 'supportsMaxOutputTokens']
AFFINITY = {'openai-session': 'T.OpenAISession{}', 'openai-no-session': 'T.OpenAINoSession{}', 'openrouter-session': 'T.OpenRouterSession{}'}
LEVELS = {'minimal': 'T.Minimal{}', 'low': 'T.Low{}', 'medium': 'T.Medium{}', 'high': 'T.High{}', 'xhigh': 'T.XHigh{}', 'max': 'T.Max{}'}

def text(value):
    return json.dumps(value, ensure_ascii=False)

def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(value)
    if float(value) == int(value) and 0 <= int(value) < 2**32:
        return f'U32.to_f64({int(value)})'
    fraction = Fraction(repr(float(value)))
    if fraction < 0 or fraction.numerator >= 2**32 or fraction.denominator >= 2**32:
        raise ValueError(f'number out of catalog range: {value}')
    return f'F64.div(U32.to_f64({fraction.numerator}), U32.to_f64({fraction.denominator}))'

def maybe(value, render):
    return 'None{}' if value is None else f'Some{{{render(value)}}}'

def boolean(value):
    return 'True{}' if value else 'False{}'

def cost(value):
    tiers = value.get('tiers')
    rendered_tiers = None if tiers is None else 'List.reverse(&2, T.ModelCostTier, ' + reduce_list(['T.ModelCostTier{' + ', '.join(number(t[k]) for k in ('input', 'output', 'cacheRead', 'cacheWrite', 'inputTokensAbove')) + '}' for t in tiers]) + ')'
    return 'T.ModelCost{' + ', '.join(number(value[k]) for k in ('input', 'output', 'cacheRead', 'cacheWrite')) + ', ' + maybe(rendered_tiers, lambda t: t) + '}'

def reduce_list(items):
    # Build lists as reversed cons chains to keep every line short.
    out = 'Nil{}'
    for item in items:
        out = f'{item} <> {out}'
    return out

def thinking_map(value):
    entries = []
    for level, mapped in value.items():
        rendered_level = 'T.Off{}' if level == 'off' else f'T.Thinking{{{LEVELS[level]}}}'
        rendered_value = 'Some{T.NullValue{}}' if mapped is None else f'Some{{T.PresentValue{{{text(mapped)}}}}}'
        entries.append(f'T.ThinkingLevelMapping{{{rendered_level}, {rendered_value}}}')
    return 'T.ThinkingLevelMap{' + ordered(entries) + '}'

def ordered(items):
    return '[' + ', '.join(items) + ']' if items else 'Nil{}'

def compat(api, value):
    if api not in ('openai-responses', 'openai-codex-responses', 'azure-openai-responses'):
        raise ValueError(f'unsupported compat for {api}')
    fields = []
    for key in RESPONSES_COMPAT:
        entry = value.get(key)
        if key == 'sessionAffinityFormat':
            fields.append(maybe(entry, lambda v: AFFINITY[v]))
        else:
            fields.append(maybe(entry, boolean))
    unknown = set(value) - set(RESPONSES_COMPAT)
    if unknown:
        raise ValueError(f'unknown compat fields: {sorted(unknown)}')
    return 'T.OpenAIResponsesCompat{' + ', '.join(fields) + '}'

def model(api, value):
    known = {'id', 'name', 'api', 'provider', 'baseUrl', 'reasoning', 'thinkingLevelMap', 'input', 'inputLimits', 'cost', 'promptCache', 'contextWindow', 'maxTokens', 'compat', 'headers'}
    unknown = set(value) - known
    if unknown:
        raise ValueError(f'unknown model fields for {value["id"]}: {sorted(unknown)}')
    inputs = ordered(['T.InputText{}' if k == 'text' else 'T.InputImage{}' for k in value['input']])
    headers = maybe(value.get('headers'), lambda h: 'Record.Record{' + ordered([f'Record.Property{{{text(k)}, {text(v)}}}' for k, v in h.items()]) + '}')
    return 'T.Model{' + ', '.join([
        text(value['id']), text(value['name']), APIS[api], text(value['provider']), text(value['baseUrl']),
        boolean(value['reasoning']), maybe(value.get('thinkingLevelMap'), thinking_map), inputs, maybe(value.get('inputLimits'), input_limits), cost(value['cost']), maybe(value.get('promptCache'), prompt_cache),
        number(value['contextWindow']), number(value['maxTokens']), 'None{}', headers, maybe(value.get('compat'), lambda c: compat(api, c)),
    ]) + '}'

def exact_keys(value, keys, what):
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
        for model_id, value in models.items():
            name = identifier(model_id)
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
