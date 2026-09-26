#!/usr/bin/env python3
"""Google Generative AI: the named upstream suites and a differential against pinned pi-mono.

The named suites (tests/google-suites.bend) print one PASS line per ported
upstream test; the names are compared with the upstream sources. The
differential runs the same parameter, wire and response cases through
packages/ai/test/google-differential.bend and
tests/google_generative_ai_reference.ts (upstream `stream`/`streamSimple`
with the real @google/genai SDK and a stubbed global fetch) and compares the
SDK parameters, wire requests and streamed messages/events exactly,
including JSON key order.

Usage: python3 tests/google_generative_ai_check.py [--backends bun native-1 native-4] [--only TEXT]
"""
from upstream_pin import UPSTREAM
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from anthropic_messages_check import build, command, decode, encode, upstream_names  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITES = ROOT / 'tests/google-suites.bend'
DIFF = ROOT / 'packages/ai/test/google-differential.bend'

VERTEX = 'the Google Vertex adapter is not ported'
NAMED = {
    'google-thinking-signature': {},
    'google-shared-convert-tools': {},
    'google-shared-gemini3-unsigned-tool-call': {'each': {
        'preserves tool call IDs for $id via $api history': ['gemini-3-pro-preview via google-generative-ai', 'gemini-3.6-flash via google-generative-ai', 'gemini-3-pro-preview via google-vertex'],
        'returns %s for %s': ['false for gemini-2.5-flash', 'true for gemini-3.6-flash', 'true for claude-sonnet-4-5', 'true for gpt-oss-120b']}},
    'google-shared-image-tool-result-routing': {},
    'google-shared-signed-empty-blocks': {},
    'google-shared-retry': {},
    'google-thinking-level-map': {'each': {
        'uses the lowest supported $name level when reasoning is omitted': ['Google Generative AI'],
        'preserves native medium effort for Gemini 3.1 Pro on $name': ['Google Generative AI'],
        'disables Gemini 2.5 thinking when reasoning is omitted on $name': ['Google Generative AI'],
        'maps Google Generative AI %s to a supported level': ['xhigh', 'max']},
        'skipped': {'maps Google Vertex extended levels': VERTEX, 'uses mapped Google Vertex levels for token budgets': VERTEX}},
    'google-raw-stop-reason': {'each': {
        'preserves MAX_TOKENS with a tool call as length for $name': ['Google Generative AI'],
        'maps STOP with a tool call to toolUse for $name': ['Google Generative AI']},
        'skipped': {'preserves raw Gemini finish reasons for Google Vertex errors': VERTEX}},
    'fetch-option': {'skipped': {
        'passes fetch through streamSimple to the Anthropic SDK': 'Anthropic case: tests/anthropic_messages_check.py',
        'passes fetch through streamSimple to OpenAI SDK adapters': 'not ported yet (OpenAI-family adapters)',
        'uses fetch for Mistral, Codex SSE, and pi-messages HTTP requests': 'not ported yet',
        'uses fetch for image generation': 'openrouter-images adapter (another port)'}},
}


def expand(name, values):
    # `$id via $api` rows and `%s for %s` rows carry both substitutions.
    if '$id via $api' in name:
        return [name.replace('$id via $api', value) for value in values]
    if name.count('%s') == 2:
        return [name.replace('%s for %s', value) for value in values]
    return [name.replace('$name', value).replace('%s', value) for value in values]


def names(suite, spec):
    each = spec.get('each', {})
    plain = {**spec, 'each': {}}
    result = []
    source = (UPSTREAM / f'packages/ai/test/{suite}.test.ts').read_text()
    for match in re.finditer(r'(?:\bit\(|\]\s*(?:as const)?\)\(|\bit\.each\(\w+\)\()\s*"((?:[^"\\]|\\.)*)"', source, re.S):
        name = match.group(1).replace('\\"', '"')
        if name in each:
            result += expand(name, each[name])
        elif name not in spec.get('skipped', {}):
            result.append(name)
    for name in list(each) + list(spec.get('skipped', {})):
        assert name in source, (suite, name)
    return result


# Differential cases
# ------------------

def user(text, timestamp=1):
    return {'role': 'user', 'content': text, 'timestamp': timestamp}


USAGE = {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 0, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}
SIG = 'AAAAAAAAAAAAAAAAAAAAAA=='


def assistant(content, model='gemini-2.5-flash', provider='google', api='google-generative-ai', stop='stop'):
    return {'role': 'assistant', 'content': content, 'api': api, 'provider': provider, 'model': model, 'usage': USAGE, 'stopReason': stop, 'timestamp': 3}


def result(call_id, text, image=False, error=False, name='lookup'):
    content = [{'type': 'text', 'text': text}] if text is not None else []
    if image:
        content.append({'type': 'image', 'data': 'aGVsbG8=', 'mimeType': 'image/png'})
    return {'role': 'toolResult', 'toolCallId': call_id, 'toolName': name, 'content': content, 'isError': error, 'timestamp': 4}


LOOKUP = {'name': 'lookup', 'description': 'Look up a value', 'parameters': {'$schema': 'http://json-schema.org/draft-07/schema#', 'type': 'object', 'properties': {'value': {'type': 'string'}}, 'required': ['value']}}
STRICT = {'name': 'strict_lookup', 'description': 'Strict lookup', 'parameters': {'type': 'object', 'properties': {'value': {'type': 'string'}, 'count': {'type': 'number'}}, 'required': ['value']}, 'constrainedSampling': {'type': 'json_schema', 'strict': 'require'}}
PREFER = {**STRICT, 'name': 'prefer_lookup', 'constrainedSampling': {'type': 'json_schema', 'strict': 'prefer'}}


def replay(model):
    return [
        user('Use the tool'),
        assistant([{'type': 'thinking', 'thinking': 'reasoning', 'thinkingSignature': SIG}, {'type': 'text', 'text': 'Looking.', 'textSignature': 'not base64!'}, {'type': 'toolCall', 'id': 'call-1', 'name': 'lookup', 'arguments': {'value': '42'}, 'thoughtSignature': SIG}], model=model, stop='toolUse'),
        result('call-1', 'found'), result('call-2', 'second', error=True), user('Thanks')]


CONTEXTS = {
    'hello': lambda model: {'messages': [user('Hello')]},
    'system-tools': lambda model: {'systemPrompt': 'You are helpful.', 'tools': [LOOKUP], 'messages': [user('Use the tool')]},
    'replay': lambda model: {'systemPrompt': 'Be brief.', 'tools': [LOOKUP], 'messages': replay(model)},
    'foreign': lambda model: {'tools': [LOOKUP], 'messages': [
        user('Start'),
        assistant([{'type': 'thinking', 'thinking': 'other reasoning', 'thinkingSignature': SIG}, {'type': 'thinking', 'thinking': '  ', 'thinkingSignature': SIG}, {'type': 'toolCall', 'id': 'call_abc|fc_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'name': 'lookup', 'arguments': {'value': 'x'}}], provider='openai', model='gpt-5.5', api='openai-responses', stop='toolUse'),
        result('call_abc|fc_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'ok'), user('Continue')]},
    'images': lambda model: {'messages': [
        {'role': 'user', 'content': [{'type': 'text', 'text': 'See'}, {'type': 'image', 'data': 'aGVsbG8=', 'mimeType': 'image/png'}], 'timestamp': 1},
        assistant([{'type': 'toolCall', 'id': 'call-a', 'name': 'read', 'arguments': {}}, {'type': 'toolCall', 'id': 'call-b', 'name': 'read', 'arguments': {}}], model=model, stop='toolUse'),
        result('call-a', 'alpha', name='read'), result('call-b', None, image=True, name='read'), user('Next')]},
    'strict': lambda model: {'tools': [STRICT, PREFER, LOOKUP], 'messages': [user('Strict')]},
    'mid-system': lambda model: {'systemPrompt': 'Base.', 'tools': [LOOKUP], 'messages': [
        user('One'), assistant([{'type': 'text', 'text': 'First.'}], model=model),
        {'role': 'system', 'content': 'Update.', 'sections': {'style': 'terse'}, 'toolsAdded': [STRICT], 'timestamp': 5}, user('Two')]},
    'blank': lambda model: {'messages': [
        {'role': 'user', 'content': [], 'timestamp': 1}, user(''), user('Real'),
        assistant([{'type': 'text', 'text': ''}, {'type': 'thinking', 'thinking': ''}, {'type': 'text', 'text': '', 'textSignature': SIG}], model=model), user('Next')]},
}

MODELS = {
    'gemini-2.5-flash': {'catalog': 'gemini-2.5-flash'},
    'gemini-2.5-pro': {'catalog': 'gemini-2.5-pro'},
    'gemini-2.5-flash-lite': {'catalog': 'gemini-2.5-flash-lite'},
    'gemini-3-flash-preview': {'catalog': 'gemini-3-flash-preview'},
    'gemini-3.1-pro-preview': {'catalog': 'gemini-3.1-pro-preview'},
    'gemini-flash-latest': {'catalog': 'gemini-flash-latest'},
    'gemma-4-31b-it': {'catalog': 'gemma-4-31b-it'},
    'levels': {'custom': {'id': 'gemini-3.8-flash', 'provider': 'test-google', 'input': ['text', 'image'], 'thinkingLevelMap': {'off': None, 'minimal': None, 'low': 'low', 'medium': 'MEDIUM', 'high': 'high', 'xhigh': 'high', 'max': None}, 'headers': {'X-Model': 'm'}}},
    'budget-map': {'custom': {'id': 'gemini-2.5-flash', 'provider': 'test-google', 'thinkingLevelMap': {'xhigh': 'high', 'max': 'extreme'}}},
    'plain': {'custom': {'id': 'custom-model', 'provider': 'test-google', 'reasoning': False}},
}

KEY = 'test-google-key'


def model_id(model):
    spec = MODELS[model]
    return spec.get('catalog') or spec['custom']['id']


def payload_cases():
    cases = []
    simple = [
        {'apiKey': KEY},
        {'apiKey': KEY, 'reasoning': 'minimal', 'temperature': 0.5, 'maxTokens': 1000},
        {'apiKey': KEY, 'reasoning': 'low', 'toolChoice': 'auto'},
        {'apiKey': KEY, 'reasoning': 'medium', 'thinkingBudgets': {'medium': 777}},
        {'apiKey': KEY, 'reasoning': 'high', 'toolChoice': 'none'},
        {'apiKey': KEY, 'reasoning': 'xhigh'},
        {'apiKey': KEY, 'reasoning': 'max', 'maxTokens': 50000},
        {},
    ]
    direct = [
        {'apiKey': KEY},
        {'apiKey': KEY, 'thinking': {'enabled': True, 'level': 'LOW'}, 'toolChoice': 'any'},
        {'apiKey': KEY, 'thinking': {'enabled': True, 'budgetTokens': -1}, 'temperature': 0},
        {'apiKey': KEY, 'thinking': {'enabled': True}},
        {'apiKey': KEY, 'thinking': {'enabled': False}, 'toolChoice': 'bogus'},
    ]
    for model in MODELS:
        for context in CONTEXTS:
            for index, options in enumerate(simple):
                if (len(cases) + index) % 4 == 0 or context in ('hello', 'replay'):
                    cases.append({'name': f'payload simple {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context](model_id(model)), 'entry': 'simple', 'options': options, 'mode': 'payload'})
            for index, options in enumerate(direct):
                if (len(cases) + index) % 5 == 0 or context in ('strict', 'foreign'):
                    cases.append({'name': f'payload stream {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context](model_id(model)), 'entry': 'stream', 'options': options, 'mode': 'payload'})
    return cases


def request_cases():
    cases = []
    options = [
        {'apiKey': KEY},
        {'apiKey': KEY, 'headers': {'User-Agent': 'custom-agent', 'X-Extra': 'e', 'X-Model': None}},
        {'apiKey': KEY, 'thinking': {'enabled': True, 'level': 'HIGH'}, 'temperature': 0.25, 'maxTokens': 99},
        {'apiKey': ''},
    ]
    for model in ('gemini-2.5-flash', 'gemini-3-flash-preview', 'levels', 'plain'):
        for index, selected in enumerate(options):
            for context in ('system-tools', 'replay', 'images'):
                cases.append({'name': f'request {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context](model_id(model)), 'entry': 'stream', 'options': selected, 'mode': 'request'})
    return cases


def data(obj):
    return 'data: ' + json.dumps(obj, separators=(',', ':')) + '\n\n'


def cand(parts=None, finish=None, **extra):
    c = {}
    if parts is not None:
        c['content'] = {'parts': parts, 'role': 'model'}
    if finish is not None:
        c['finishReason'] = finish
    return {'candidates': [c], **extra}


USAGE_META = {'usageMetadata': {'promptTokenCount': 120, 'cachedContentTokenCount': 20, 'candidatesTokenCount': 30, 'thoughtsTokenCount': 7, 'totalTokenCount': 157}}

BODIES = {
    'text': data({**cand([{'text': 'Hel'}]), 'responseId': 'r1'}) + data({**cand([{'text': 'lo'}], 'STOP'), **USAGE_META}),
    'thinking': data(cand([{'text': 'Why', 'thought': True, 'thoughtSignature': 'c2ln'}, {'text': ' because', 'thought': True}])) + data(cand([{'text': 'Answer', 'thoughtSignature': 'dGV4dA=='}, {'text': '!', 'thoughtSignature': ''}], 'STOP')),
    'tools': data({**cand([{'text': 'Calling'}, {'functionCall': {'id': 'call-1', 'name': 'lookup', 'args': {'value': '42'}}, 'thoughtSignature': 'c2ln'}, {'functionCall': {'id': 'call-2', 'name': 'other', 'args': {}}}], 'STOP'), 'responseId': ''}) + data({'responseId': 'late'}),
    'length': data(cand([{'functionCall': {'id': 'x', 'name': 'echo', 'args': {'value': 'truncated'}}}], 'MAX_TOKENS')),
    'safety': data({**cand(None, 'SAFETY'), **USAGE_META}),
    'unknown-reason': data(cand([{'text': 'a'}], 'NEW_REASON')),
    'no-reason': data(cand([{'text': 'a'}])),
    'crlf': 'data: ' + json.dumps(cand([{'text': 'c'}], 'STOP')) + '\r\n\r\n',
    'cr': 'data: ' + json.dumps(cand([{'text': 'r'}], 'STOP')) + '\r\r',
    'incomplete': data(cand([{'text': 'a'}], 'STOP')) + 'data: {"candidates"',
    'trailing-space': data(cand([{'text': 'a'}], 'STOP')) + '  \n',
    'comment': ': hi\n\n' + 'event: x\n' + data(cand([{'text': 'a'}], 'STOP')),
    'error-chunk': json.dumps({'error': {'code': 429, 'message': 'quota', 'status': 'RESOURCE_EXHAUSTED'}}),
    'error-low': json.dumps({'error': {'code': 200, 'message': 'odd'}}),
    'usage-only': data({**cand([{'text': 'x'}], 'STOP'), 'usageMetadata': {'promptTokenCount': 5}}),
}


def response_cases():
    return [{'name': f'response {name}', 'model': MODELS['gemini-2.5-flash'], **CONTEXTS['hello']('gemini-2.5-flash'), 'entry': 'stream', 'options': {'apiKey': 'test-key'}, 'mode': 'response', 'body': body} for name, body in BODIES.items()]


# Comparison
# ----------

GENERATED = re.compile(r'^(.*)_\d+_(\d+)$')


def normalized(value):
    # Generated tool call ids embed Date.now(); event partials are live
    # references upstream and snapshots natively.
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            if key in ('timestamp', 'partial'):
                continue
            if key == 'id' and isinstance(item, str) and GENERATED.match(item):
                item = GENERATED.sub(r'\1_<now>_\2', item)
            out[key] = normalized(item)
        return out
    if isinstance(value, list):
        return [normalized(item) for item in value]
    return value


def normalize(case, value):
    if case['mode'] == 'request':
        if value is None or 'url' not in value:
            return value
        headers = {k: v for k, v in value.get('headers', {}).items() if k != 'x-goog-api-client'}
        return {'url': value['url'], 'method': value['method'].lower(), 'headers': dict(sorted(headers.items())), 'body': value['body']}
    if case['mode'] == 'response':
        return normalized(value)
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False)


def run_bend(cmd, cases):
    results = []
    for start_index in range(0, len(cases), 24):
        chunk = cases[start_index:start_index + 24]
        run = subprocess.run(cmd + [encode(c) for c in chunk], cwd=ROOT, capture_output=True, text=True, timeout=1800)
        assert run.returncode == 0, (run.stdout[-2000:], run.stderr[-4000:])
        lines = [decode(line[2:]) for line in run.stdout.splitlines() if line.startswith('R ')]
        assert len(lines) == len(chunk), run.stdout[-2000:]
        results += lines
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
    parser.add_argument('--only', default='')
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--skip-suites', action='store_true')
    arguments = parser.parse_args()
    prefix = str(ROOT / 'build/google')
    if not arguments.no_build:
        if not arguments.skip_suites:
            build(SUITES, prefix + '-suites', arguments.backends)
        build(DIFF, prefix + '-differential', arguments.backends)
    expected = []
    for suite, spec in NAMED.items():
        expected += ['PASS ' + name for name in names(suite, spec)]
    cases = [c for c in payload_cases() + request_cases() + response_cases() if arguments.only in c['name']]
    oracle = json.loads(subprocess.check_output(['bun', 'tests/google_generative_ai_reference.ts'], input=json.dumps({'cases': cases}), text=True, cwd=ROOT))
    failures = 0
    for backend in arguments.backends:
        if not arguments.skip_suites and not arguments.only:
            output = subprocess.run(command(prefix + '-suites', backend), cwd=ROOT, capture_output=True, text=True, timeout=3600)
            lines = output.stdout.splitlines()
            if output.returncode != 0 or lines != expected:
                failures += 1
                print(f'FAIL {backend} named suites: exit {output.returncode}, missing {[n for n in expected if n not in lines][:5]}, extra {[l for l in lines if l not in expected][:5]}, stderr {output.stderr[-500:]}')
            else:
                print(f'{backend}: {len(lines)} named upstream Google tests pass')
        actual = run_bend(command(prefix + '-differential', backend), cases)
        mismatches = 0
        for case, want, got in zip(cases, oracle, actual):
            if normalize(case, want) != normalize(case, got):
                mismatches += 1
                if mismatches <= 8:
                    print(f'FAIL {backend} {case["name"]}:\n  bend     {json.dumps(normalize(case, got))[:1500]}\n  upstream {json.dumps(normalize(case, want))[:1500]}')
        failures += mismatches
        print(f'{backend}: {len(cases) - mismatches} of {len(cases)} differential cases match pinned pi-mono')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
