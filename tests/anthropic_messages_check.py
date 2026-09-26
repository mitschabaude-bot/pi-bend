#!/usr/bin/env python3
"""Anthropic Messages: the named upstream suites and a differential against pinned pi-mono.

The named suites (tests/anthropic-suites.bend) print one PASS line per ported
upstream test; the names are compared with the upstream sources. The
differential runs the same request, wire and response cases through
packages/ai/test/anthropic-differential.bend and tests/anthropic_messages_reference.ts
(upstream `stream`/`streamSimple`) and compares params, wire requests and
streamed messages/events exactly, including JSON key order.

Usage: python3 tests/anthropic_messages_check.py [--backends bun native-1 native-4] [--only TEXT]
"""
from upstream_pin import UPSTREAM
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
SUITES = ROOT / 'tests/anthropic-suites.bend'
DIFF = ROOT / 'packages/ai/test/anthropic-differential.bend'

# Named upstream suites. `each` expands it.each tables; `skipped` lists tests
# that are not ported, with the reason (they stay pending in the inventory).
NAMED = {
    'anthropic-sse-parsing': {},
    'anthropic-temperature-compat': {},
    'anthropic-force-adaptive-thinking': {'each': {'uses adaptive thinking effort without a token budget for Kimi Coding %s': ['kimi-for-coding', 'k3', 'kimi-for-coding-highspeed']}},
    'anthropic-thinking-disable': {'skipped': {'disables thinking for Claude reasoning models': 'E2E: needs ANTHROPIC_API_KEY'}},
    'anthropic-empty-thinking-signature-compat': {'each': {
        'preserves unsigned thinking for Fireworks %s': ['accounts/fireworks/models/deepseek-v4-flash-0731', 'accounts/fireworks/models/deepseek-v4-flash-vision-exp', 'accounts/fireworks/models/deepseek-v4-pro-0813', 'accounts/fireworks/models/qwen3p8-max', 'accounts/fireworks/models/qwen3p8-2p4t-a95b', 'accounts/fireworks/models/kimi-k2p6'],
        'allows empty signatures for Kimi Coding %s': ['k3']}},
    'anthropic-cache-write-1h-cost': {},
    'anthropic-mid-conversation-effort': {'each': {'preserves native effort %s': ['low', 'medium', 'high', 'xhigh', 'max']}},
    'anthropic-eager-tool-input-compat': {},
    'github-copilot-anthropic': {},
    'anthropic-auth-token': {'skipped': {
        'threads authContext ANTHROPIC_AUTH_TOKEN through request headers': 'needs the Models registry streamSimple (createModels/setProvider), not ported',
        'preserves OAuth request shaping for ANTHROPIC_OAUTH_TOKEN': 'needs the Models registry streamSimple (createModels/setProvider), not ported',
        'lets explicit request headers override ANTHROPIC_AUTH_TOKEN': 'needs the Models registry streamSimple (createModels/setProvider), not ported'}},
}


def upstream_names(suite, spec):
    source = (UPSTREAM / f'packages/ai/test/{suite}.test.ts').read_text()
    names = []
    for match in re.finditer(r'\bit(?:\.each\([^)]*\]\s*(?:as const)?\))?\(\s*"((?:[^"\\]|\\.)*)"', source, re.S):
        name = match.group(1).replace('\\"', '"')
        if name in spec.get('each', {}):
            names += [name.replace('%s', value) for value in spec['each'][name]]
        elif name not in spec.get('skipped', {}):
            names.append(name)
    for name in spec.get('each', {}):
        assert name in source, (suite, name)
    for name in spec.get('skipped', {}):
        assert name in source, (suite, name)
    return names


def build(entry, prefix, backends):
    if 'bun' in backends:
        subprocess.run(['bun', BEND, str(entry), '-o', prefix + '.js'], cwd=ROOT, check=True)
    if any(b.startswith('native') for b in backends):
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry.relative_to(ROOT)), prefix], cwd=ROOT, check=True)


def command(prefix, backend):
    return ['bun', prefix + '.js'] if backend == 'bun' else [prefix, '--threads', backend[-1]]


# Differential cases
# ------------------

def user(text, timestamp=1):
    return {'role': 'user', 'content': text, 'timestamp': timestamp}


USAGE = {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 0, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}


def assistant(content, provider='anthropic', model='claude-opus-5', api='anthropic-messages', stop='stop', **extra):
    return {'role': 'assistant', 'content': content, 'api': api, 'provider': provider, 'model': model, 'usage': USAGE, 'stopReason': stop, 'timestamp': 3, **extra}


def result(call_id, text, image=False, error=False, name='lookup'):
    content = [{'type': 'text', 'text': text}] if text is not None else []
    if image:
        content.append({'type': 'image', 'data': 'aGVsbG8=', 'mimeType': 'image/png'})
    return {'role': 'toolResult', 'toolCallId': call_id, 'toolName': name, 'content': content, 'isError': error, 'timestamp': 4}


LOOKUP = {'name': 'lookup', 'description': 'Look up a value', 'parameters': {'type': 'object', 'properties': {'value': {'type': 'string'}}, 'required': ['value']}}
READ = {'name': 'read', 'description': 'Read a file', 'parameters': {'type': 'object', 'properties': {'path': {'type': 'string'}}, 'required': ['path']}}
TODO = {'name': 'todowrite', 'description': 'Write a todo', 'parameters': {'type': 'object', 'properties': {'task': {'type': 'string'}}}}
STRICT = {'name': 'strict_lookup', 'description': 'Strict lookup', 'parameters': {'title': 'StrictInput', 'type': 'object', 'properties': {'value': {'type': 'string'}, 'count': {'type': 'number'}}, 'required': ['value']}, 'constrainedSampling': {'type': 'json_schema', 'strict': 'require'}}
PREFER = {**STRICT, 'name': 'prefer_lookup', 'constrainedSampling': {'type': 'json_schema', 'strict': 'prefer'}}

CONTEXTS = {
    'hello': {'messages': [user('Hello')]},
    'system-tools': {'systemPrompt': 'You are helpful.', 'tools': [LOOKUP, READ], 'messages': [user('Use the tool')]},
    'replay': {'systemPrompt': 'Be brief.', 'tools': [LOOKUP], 'messages': [
        user('Use the tool'),
        assistant([{'type': 'thinking', 'thinking': 'reasoning', 'thinkingSignature': 'sig'}, {'type': 'text', 'text': 'Looking.'}, {'type': 'toolCall', 'id': 'toolu_1', 'name': 'lookup', 'arguments': {'value': '42'}}], stop='toolUse'),
        result('toolu_1', 'found'), user('Thanks')]},
    'images': {'messages': [
        {'role': 'user', 'content': [{'type': 'text', 'text': 'See'}, {'type': 'image', 'data': 'aGVsbG8=', 'mimeType': 'image/png'}, {'type': 'text', 'text': '   '}], 'timestamp': 1},
        assistant([{'type': 'toolCall', 'id': 'toolu_img', 'name': 'lookup', 'arguments': {}}], stop='toolUse'),
        result('toolu_img', None, image=True), result('toolu_missing', 'second', error=True)]},
    'cross-provider': {'tools': [LOOKUP], 'messages': [
        user('Start'),
        assistant([{'type': 'thinking', 'thinking': 'other reasoning', 'thinkingSignature': 'rs_opaque'}, {'type': 'text', 'text': 'Calling.'}, {'type': 'toolCall', 'id': 'call_abc|fc_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'name': 'lookup', 'arguments': {'value': 'x'}}], provider='openai', model='gpt-5.5', api='openai-responses', stop='toolUse'),
        result('call_abc|fc_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'ok'), user('Continue')]},
    'blank-parts': {'messages': [
        user('  '), user('Real question'),
        assistant([{'type': 'text', 'text': '  '}, {'type': 'thinking', 'thinking': '   ', 'thinkingSignature': ''}, {'type': 'thinking', 'thinking': 'unsigned', 'thinkingSignature': '  '}, {'type': 'thinking', 'thinking': '[Reasoning redacted]', 'thinkingSignature': 'opaque', 'redacted': True}]),
        assistant([{'type': 'text', 'text': ''}]), user('Next')]},
    'orphan-call': {'messages': [
        user('Go'), assistant([{'type': 'toolCall', 'id': 'toolu_orphan', 'name': 'lookup', 'arguments': {'value': 'a'}}], stop='toolUse'), user('Interrupted')]},
    'mid-system': {'tools': [LOOKUP], 'systemPrompt': 'Base prompt.', 'messages': [
        user('One'), assistant([{'type': 'text', 'text': 'First.'}]),
        {'role': 'system', 'content': 'Update rules.', 'sections': {'style': 'terse', 'old': None}, 'toolsAdded': [READ], 'toolsRemoved': [{'name': 'lookup'}], 'timestamp': 5},
        user('Two'), assistant([{'type': 'toolCall', 'id': 'toolu_r', 'name': 'read', 'arguments': {'path': 'a'}}], stop='toolUse'),
        {'role': 'system', 'content': 'Between.', 'timestamp': 6}, result('toolu_r', 'contents', name='read'), user('Three')]},
    'oauth-tools': {'systemPrompt': 'Act.', 'tools': [READ, TODO, LOOKUP], 'messages': [
        user('Read'), assistant([{'type': 'toolCall', 'id': 'toolu_x', 'name': 'todowrite', 'arguments': {'task': 't'}}], stop='toolUse'), result('toolu_x', 'done', name='todowrite')]},
    'strict-tools': {'tools': [STRICT, PREFER, LOOKUP], 'messages': [user('Strict')]},
    'managed-history': {'messages': [
        user('one'), assistant([{'type': 'thinking', 'thinking': 'r', 'thinkingSignature': 's'}, {'type': 'text', 'text': 'a'}], provider='anthropic', model='claude-fable-5-1', providerThinkingLevel='low'),
        user('two'), assistant([{'type': 'text', 'text': 'b'}], provider='anthropic', model='claude-fable-5-1', providerThinkingLevel='bogus'), user('three')]},
}

MODELS = {
    'opus-5': {'catalog': ['anthropic', 'claude-opus-5']},
    'opus-4-8': {'catalog': ['anthropic', 'claude-opus-4-8']},
    'opus-4-6': {'catalog': ['anthropic', 'claude-opus-4-6']},
    'sonnet-4-5': {'catalog': ['anthropic', 'claude-sonnet-4-5']},
    'haiku-4-5': {'catalog': ['anthropic', 'claude-haiku-4-5']},
    'fable-5': {'catalog': ['anthropic', 'claude-fable-5']},
    'fable-5-1': {'catalog': ['anthropic', 'claude-fable-5-1']},
    'copilot-sonnet': {'catalog': ['github-copilot', 'claude-sonnet-4.6']},
    'copilot-opus-4-7': {'catalog': ['github-copilot', 'claude-opus-4.7']},
    'kimi-k3': {'catalog': ['kimi-coding', 'k3']},
    'kimi-coding': {'catalog': ['kimi-coding', 'kimi-for-coding']},
    'openrouter-haiku-3': {'catalog': ['openrouter', 'anthropic/claude-3-haiku']},
    'openrouter-fable': {'catalog': ['openrouter', 'anthropic/claude-fable-5.1']},
    'fireworks': {'catalog': ['fireworks', 'accounts/fireworks/models/deepseek-v4-flash-0731']},
    'vercel': {'catalog': ['vercel-ai-gateway', 'anthropic/claude-sonnet-4.5']},
    'native-changes': {'custom': {'id': 'native-model', 'provider': 'custom', 'reasoning': True, 'compat': {'supportsMidConvoSystemMessages': True, 'supportsMidConvoToolChanges': True}}},
    'mid-system-only': {'custom': {'id': 'mid-model', 'provider': 'custom', 'reasoning': True, 'compat': {'supportsMidConvoSystemMessages': True}}},
    'strict-custom': {'custom': {'id': 'strict-model', 'provider': 'custom', 'reasoning': True, 'compat': {'supportsStrictTools': True, 'supportsCacheControlOnTools': False, 'supportsLongCacheRetention': False, 'supportsEagerToolInputStreaming': False}}},
    'fallbacks': {'catalog': ['anthropic', 'claude-opus-5'], 'compat': {'allowedFallbackModels': [{'provider': 'anthropic', 'model': 'claude-opus-4-8', 'cost': {'input': 5, 'output': 25, 'cacheRead': 0.5, 'cacheWrite': 6.25}}]}},
    'affinity': {'custom': {'id': 'affinity-model', 'provider': 'custom', 'baseUrl': 'https://gateway.example/anthropic/', 'compat': {'sendSessionAffinityHeaders': True}, 'headers': {'X-Model': 'm', 'anthropic-beta': 'model-beta, other ,model-beta'}}},
    'managed-custom': {'custom': {'id': 'claude-fable-5-1', 'provider': 'anthropic', 'reasoning': True, 'thinkingLevelMap': {'off': None, 'minimal': 'low', 'low': 'low', 'medium': 'medium', 'high': 'high', 'max': 'max'}, 'compat': {'forceAdaptiveThinking': True, 'supportsMidConvoEffort': True}}},
}

KEY = 'test-key'
OAUTH = 'sk-ant-oat01-test'


def payload_cases():
    cases = []
    simple_options = [
        {'apiKey': KEY},
        {'apiKey': KEY, 'reasoning': 'low', 'temperature': 0.5},
        {'apiKey': KEY, 'reasoning': 'high', 'maxTokens': 4000},
        {'apiKey': KEY, 'reasoning': 'xhigh', 'cacheRetention': 'long', 'thinkingBudgets': {'high': 5000}},
        {'apiKey': KEY, 'reasoning': 'max', 'cacheRetention': 'none', 'toolChoice': 'auto'},
        {'apiKey': KEY, 'reasoning': 'minimal', 'maxTokens': 1500, 'metadata': {'user_id': 'u1', 'other': 1}},
        {'apiKey': KEY, 'temperature': 0, 'toolChoice': 'none', 'metadata': {'user_id': 7}},
        {'apiKey': OAUTH, 'reasoning': 'medium'},
    ]
    direct_options = [
        {'apiKey': KEY},
        {'apiKey': KEY, 'thinkingEnabled': True, 'effort': 'high', 'temperature': 1, 'toolChoice': 'auto'},
        {'apiKey': KEY, 'thinkingEnabled': True, 'thinkingBudgetTokens': 2048, 'thinkingDisplay': 'omitted', 'interleavedThinking': False},
        {'apiKey': KEY, 'thinkingEnabled': False, 'toolChoice': {'type': 'tool', 'name': 'lookup'}},
        {'apiKey': KEY, 'thinkingEnabled': True, 'thinkingBudgetTokens': 0, 'toolChoice': 'any', 'cacheRetention': 'long'},
        {'apiKey': OAUTH, 'thinkingEnabled': True, 'effort': 'medium', 'cacheRetention': 'short'},
        {'apiKey': KEY, 'headers': {'anthropic-beta': ' custom-a, custom-b,custom-a '}},
        {'apiKey': KEY, 'headers': {'anthropic-beta': None}},
    ]
    for model in MODELS:
        for context in CONTEXTS:
            for index, options in enumerate(simple_options):
                if (len(cases) + index) % 5 == 0 or context in ('replay', 'hello'):
                    cases.append({'name': f'payload simple {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context], 'entry': 'simple', 'options': options, 'mode': 'payload'})
            for index, options in enumerate(direct_options):
                if (len(cases) + index) % 6 == 0 or context in ('mid-system', 'oauth-tools', 'strict-tools', 'managed-history'):
                    cases.append({'name': f'payload stream {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context], 'entry': 'stream', 'options': options, 'mode': 'payload'})
    return cases


def request_cases():
    cases = []
    options = [
        {'apiKey': KEY},
        {'apiKey': OAUTH},
        {'headers': {'Authorization': 'Bearer gateway-token'}},
        {'apiKey': KEY, 'headers': {'User-Agent': 'custom-client', 'X-Extra': 'e', 'accept': None}},
        {'apiKey': KEY, 'sessionId': 'session-1', 'cacheRetention': 'short'},
        {'apiKey': KEY, 'sessionId': 'session-2', 'cacheRetention': 'none'},
        {'apiKey': KEY, 'headers': {'anthropic-beta': None, 'x-api-key': None}},
    ]
    for model in ('opus-5', 'fable-5-1', 'copilot-sonnet', 'kimi-coding', 'openrouter-haiku-3', 'affinity', 'fallbacks', 'strict-custom'):
        for index, selected in enumerate(options):
            for context in ('system-tools', 'images'):
                cases.append({'name': f'request {model} {context} #{index}', 'model': MODELS[model], **CONTEXTS[context], 'entry': 'stream', 'options': selected, 'mode': 'request'})
    return cases


def sse(events, separator='\n'):
    parts = []
    for event in events:
        name, data = (event if isinstance(event, tuple) else (event['type'], json.dumps(event, separators=(',', ':'))))
        parts.append(f'event: {name}{separator}data: {data}{separator}')
    return separator.join(parts)


def start(ident='msg_1', model='claude-opus-5', usage=None, **extra):
    return {'type': 'message_start', 'message': {'id': ident, 'model': model, 'usage': usage or {'input_tokens': 12, 'output_tokens': 0}, **extra}}


def block(index, content):
    return {'type': 'content_block_start', 'index': index, 'content_block': content}


def delta(index, value):
    return {'type': 'content_block_delta', 'index': index, 'delta': value}


def stop(index):
    return {'type': 'content_block_stop', 'index': index}


def finish(reason='end_turn', usage=None, **extra):
    return {'type': 'message_delta', 'delta': {'stop_reason': reason, **extra}, 'usage': usage if usage is not None else {'output_tokens': 5}}


END = {'type': 'message_stop'}

BODIES = {
    'text': sse([start(), block(0, {'type': 'text', 'text': ''}), delta(0, {'type': 'text_delta', 'text': 'Hel'}), delta(0, {'type': 'text_delta', 'text': 'lo'}), stop(0), finish(), END]),
    'thinking-tool': sse([start('msg_tool', 'kimi-for-coding', {'input_tokens': 100, 'output_tokens': 0, 'cache_read_input_tokens': 3, 'cache_creation_input_tokens': 4}), block(0, {'type': 'thinking', 'thinking': 'reason', 'signature': 'sig'}), delta(0, {'type': 'thinking_delta', 'thinking': 'ing'}), delta(0, {'type': 'signature_delta', 'signature': '-tail'}), stop(0), block(2, {'type': 'tool_use', 'id': 'toolu_2', 'name': 'lookup', 'input': {}}), delta(2, {'type': 'input_json_delta', 'partial_json': '{"value":'}), delta(2, {'type': 'input_json_delta', 'partial_json': '"42"}'}), stop(2), finish('tool_use', {'output_tokens': 20, 'output_tokens_details': {'thinking_tokens': 8}}), END]),
    'redacted': sse([start('msg_r', usage={'input_tokens': 7, 'output_tokens': 0}), block(0, {'type': 'redacted_thinking', 'data': 'opaque'}), stop(0), block(1, {'type': 'text', 'text': 'x'}), stop(1), finish('max_tokens', {'output_tokens': 10}), END]),
    'missing-stop': sse([start(), block(0, {'type': 'text', 'text': 'partial'}), stop(0)]),
    'no-reason': sse([start(), block(0, {'type': 'text', 'text': 'a'}), stop(0), END]),
    'refusal-empty': sse([start(), finish('refusal', stop_details={'explanation': ''}), END]),
    'pause': sse([start(), finish('pause_turn'), END]),
    'unknown-reason': sse([start(), finish('model_context_window_exceeded'), END]),
    'late-fallback': sse([start(), block(0, {'type': 'text', 'text': 'partial'}), stop(0), block(1, {'type': 'fallback', 'from': {'model': 'claude-opus-5'}, 'to': {'model': 'claude-opus-4-8'}})]),
    'early-fallback': sse([start('msg_f', 'claude-opus-4-8'), block(0, {'type': 'fallback', 'from': {'model': 'claude-opus-5'}, 'to': {'model': 'claude-opus-4-8'}}), block(1, {'type': 'text', 'text': 'ok'}), stop(1), finish(usage={'input_tokens': 1000, 'output_tokens': 100, 'cache_read_input_tokens': 10}), END]),
    'error-event': sse([start(), ('error', '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}')]),
    'malformed': sse([start(), ('content_block_start', '{not json')]),
    'unknown-blocks': sse([start(), block(0, {'type': 'server_tool_use', 'id': 's', 'name': 'web'}), delta(0, {'type': 'text_delta', 'text': 'ignored'}), stop(0), block(1, {'type': 'text'}), delta(1, {'type': 'thinking_delta', 'thinking': 'wrong kind'}), delta(1, {'type': 'text_delta', 'text': 't'}), stop(1), stop(1), finish(), END, ('ping', '{}'), block(2, {'type': 'text', 'text': 'late'})]),
    'crlf': sse([start(), block(0, {'type': 'text', 'text': 'crlf'}), stop(0), finish(), END], '\r\n'),
    'comments': ': keepalive\n\n' + sse([start(), block(0, {'type': 'text', 'text': 'c'}), stop(0), finish(), END]) + '\n\n: done',
    'multiline-data': 'event: message_start\ndata: {"type":"message_start",\ndata: "message":{"id":"m","usage":{"input_tokens":1,"output_tokens":0}}}\n\n' + sse([finish(), END]),
    'transformations': sse([start(input_transformations=[{'type': 'thinking_dropped', 'path': 'messages.1.content.0', 'reason': 'prefix_binding_mismatch'}]), finish(input_transformations=[{'type': 'thinking_dropped', 'path': 'messages.3.content.0'}]), END]),
    'empty-transformations': sse([start(input_transformations=[{'type': 'x'}]), finish(input_transformations=[]), END]),
    'usage-nulls': sse([start(usage={'input_tokens': None, 'output_tokens': 3, 'cache_creation': {'ephemeral_1h_input_tokens': 2}}), finish(usage={'input_tokens': 9, 'output_tokens': None, 'cache_read_input_tokens': 4}), END]),
    'oauth-tool': sse([start(), block(0, {'type': 'tool_use', 'id': 'toolu_cc', 'name': 'TodoWrite', 'input': {'task': 'init'}}), stop(0), block(1, {'type': 'tool_use', 'id': 'toolu_rd', 'name': 'Read', 'input': {}}), delta(1, {'type': 'input_json_delta', 'partial_json': '{"path":"x'}), stop(1), finish('tool_use'), END]),
}


def response_cases():
    cases = []
    for name, body in BODIES.items():
        model = 'fallbacks' if 'fallback' in name else 'opus-5'
        context = 'oauth-tools' if name == 'oauth-tool' else 'hello'
        cases.append({'name': f'response {name}', 'model': MODELS[model], **CONTEXTS[context], 'entry': 'stream', 'options': {}, 'mode': 'response', 'body': body})
    cases.append({'name': 'response managed level', 'model': MODELS['fable-5-1'], **CONTEXTS['hello'], 'entry': 'stream', 'options': {'effort': 'low'}, 'mode': 'response', 'body': BODIES['text']})
    return cases


# Named-suite fixtures
# --------------------

def named_suite_bodies():
    """packages/ai/test/anthropic-sse-bodies.bend: the named suites' response bodies."""
    def js(v): return json.dumps(v, separators=(',',':'), ensure_ascii=False)
    def b(s):
        out=''
        for ch in s:
            if ch=='\\': out+='\\\\'
            elif ch=='"': out+='\\"'
            elif ch=='\n': out+='\\n'
            elif ch=='\t': out+='\\t'
            elif ord(ch)<32: out+='\\u{%x}'%ord(ch)
            else: out+=ch
        return '"'+out+'"'
    def body(events):
        # createSseResponse: `event: X\ndata: Y\n` joined by "\n"
        return "\n".join(f"event: {e}\ndata: {d}\n" for e,d in events)
    def ev(obj): return (obj["type"], js(obj))
    minimal=[
     ev({"type":"message_start","message":{"id":"msg_test","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
     ev({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}),
     ev({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}),
     ev({"type":"content_block_stop","index":0}),
     ev({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}),
     ev({"type":"message_stop"}),
    ]
    def response_model(model, block):
        return [
         ev({"type":"message_start","message":{"id":"msg_response_model","model":model,"usage":{"input_tokens":100,"output_tokens":0}}}),
         ev({"type":"content_block_start","index":0,"content_block":block}),
         ev({"type":"content_block_stop","index":0}),
         ev({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":100,"output_tokens":20}}),
         ev({"type":"message_stop"}),
        ]
    bodies={}
    bodies['minimal']=body(minimal)
    bodies['relabel']=body(response_model("kimi-for-coding",{"type":"thinking","thinking":"reasoning","signature":"signature"}))
    bodies['fallbackCost']=body(response_model("fallback-model",{"type":"text","text":"done"}))
    bodies['lateFallback']=body([
     ev({"type":"message_start","message":{"id":"msg_fallback","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":0}}}),
     ev({"type":"content_block_start","index":0,"content_block":{"type":"text","text":"partial"}}),
     ev({"type":"content_block_stop","index":0}),
     ev({"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"claude-opus-5"},"to":{"model":"claude-opus-4-8"}}}),
    ])
    t_events=list(minimal)
    t_events[0]=ev({"type":"message_start","message":{"id":"msg_transformations","model":"claude-fable-5-1","usage":{"input_tokens":12,"output_tokens":0},"input_transformations":[{"type":"thinking_dropped","path":"messages.1.content.0","reason":"prefix_binding_mismatch"}]}})
    delta=json.loads(minimal[4][1]); delta["input_transformations"]=[{"type":"thinking_dropped","path":"messages.3.content.0","reason":"model_binding_mismatch"}]
    t_events[4]=("message_delta",js(delta))
    bodies['transformations']=body(t_events)
    malformed=r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"A\H\",\"text\":\"col1	col2\"}"}}'
    bodies['malformed']=body([
     ev({"type":"message_start","message":{"id":"msg_test","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
     ev({"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_test","name":"edit","input":{}}}),
     ("content_block_delta",malformed),
     ev({"type":"content_block_stop","index":0}),
     ev({"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}),
     ev({"type":"message_stop"}),
    ])
    bodies['initialContent']=body([
     ev({"type":"message_start","message":{"id":"msg_initial_content","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
     ev({"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Initial text"}}),
     ev({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" plus delta"}}),
     ev({"type":"content_block_stop","index":0}),
     ev({"type":"content_block_start","index":1,"content_block":{"type":"thinking","thinking":"Initial thinking","signature":"initial signature"}}),
     ev({"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":" plus delta"}}),
     ev({"type":"content_block_delta","index":1,"delta":{"type":"signature_delta","signature":" plus delta"}}),
     ev({"type":"content_block_stop","index":1}),
     ev({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}),
     ev({"type":"message_stop"}),
    ])
    explanation="This request triggered restrictions on violative cyber content and was blocked under Anthropic's Usage Policy. To learn more, provide feedback, or request an exemption based on how you use Claude, visit our help center: https://support.claude.com/en/articles/14604842-real-time-cyber-safeguards-on-claude."
    bodies['refusal']=body([
     ev({"type":"message_start","message":{"id":"msg_01XFUDYJgAACzvnptvVoYEL","usage":{"input_tokens":412,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
     ev({"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber","explanation":explanation}},"usage":{"input_tokens":412,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}),
     ev({"type":"message_stop"}),
    ])
    bodies['sensitive']=body([
     ev({"type":"message_start","message":{"id":"msg_sensitive","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}),
     ev({"type":"message_delta","delta":{"stop_reason":"sensitive"},"usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}),
     ev({"type":"message_stop"}),
    ])
    bodies['noUsage']=body([e if e[0]!="message_delta" else ("message_delta",js({"type":"message_delta","delta":{"stop_reason":"end_turn"}})) for e in minimal])
    bodies['afterStop']=body(minimal+[("done","[DONE]"),("proxy.stats","not json")])
    def cache_events(cc):
        su={"input_tokens":100,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":1000000}
        if cc: su["cache_creation"]=cc
        return body([
         ev({"type":"message_start","message":{"id":"msg_test","usage":su}}),
         ev({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}),
         ev({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}),
         ev({"type":"content_block_stop","index":0}),
         ev({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":100,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":1000000}}),
         ev({"type":"message_stop"}),
        ])
    bodies['cache1h']=cache_events({"ephemeral_5m_input_tokens":600000,"ephemeral_1h_input_tokens":400000})
    bodies['cache5m']=cache_events(None)
    # mid-conversation-effort fetch body: `event: X\ndata: Y\n\n` joined.
    mce=[{"type":"message_start","message":{"id":"msg_test","model":"claude-fable-5-1","usage":{"input_tokens":1,"output_tokens":0}}},{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":1,"output_tokens":1}},{"type":"message_stop"}]
    bodies['effortFetch']="".join(f"event: {e['type']}\ndata: {js(e)}\n\n" for e in mce)
    # copilot mock body
    cop=[f"event: message_start\ndata: {js({'type':'message_start','message':{'id':'msg_test','usage':{'input_tokens':10,'output_tokens':0}}})}\n", f"event: message_delta\ndata: {js({'type':'message_delta','delta':{'stop_reason':'end_turn'},'usage':{'output_tokens':5}})}\n"]
    bodies['copilot']="\n".join(cop)
    auth=[f"event: message_start\ndata: {js({'type':'message_start','message':{'id':'msg_test','usage':{'input_tokens':1,'output_tokens':0}}})}\n", f"event: message_delta\ndata: {js({'type':'message_delta','delta':{'stop_reason':'end_turn'},'usage':{'output_tokens':1}})}\n", f"event: message_stop\ndata: {js({'type':'message_stop'})}\n"]
    bodies['authToken']="\n".join(auth)
    out=["import Base","","# Response bodies of pi-mono f07218c4d's Anthropic suites, written as their","# createSseResponse/mocks write them (tests/anthropic_messages_check.py --write-bodies).",""]
    for k,v in bodies.items():
        out.append(f"def {k}() -> String: {b(v)}")
        out.append("")
    out.append(f"def explanation() -> String: {b(explanation)}")
    return "\n".join(out)+"\n"


# Comparison
# ----------

def ordered(text):
    return json.loads(text, object_pairs_hook=lambda pairs: [('{}', pairs)])


PARSE_ERROR = re.compile(r'(Could not parse Anthropic SSE event [^:]*: ).*?(; data=)', re.S)


def strip_times(value):
    # Adaptations (docs/source-coverage-reviews.json, anthropic-messages.ts):
    # event partials are live references upstream and snapshots natively;
    # JSON.parse's engine-specific message is not reproduced; a block still
    # open when the stream completes leaks upstream's scratch `index` field.
    if isinstance(value, dict):
        return {k: strip_times(v) for k, v in value.items() if k not in ('timestamp', 'partial') and not (k == 'index' and value.get('type') in ('text', 'thinking', 'toolCall'))}
    if isinstance(value, list):
        return [strip_times(v) for v in value]
    if isinstance(value, str):
        return PARSE_ERROR.sub(r'\1<parse error>\2', value)
    return value


def normalize(case, value):
    mode = case['mode']
    if mode == 'request':
        if value is None or 'thrown' in value:
            return value
        headers = {k: v for k, v in value.get('headers', {}).items() if not k.startswith('x-stainless-')}
        body = json.loads(value['body']) if value.get('body') else None
        return {'url': value['url'], 'method': value['method'].lower(), 'headers': dict(sorted(headers.items())), 'body': json.dumps(body, separators=(',', ':'), ensure_ascii=False)}
    if mode == 'response':
        return strip_times(value)
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False)


def decode(line):
    return json.loads(''.join(chr(int(part)) for part in line.split(',')))


def encode(case):
    return ','.join(str(ord(c)) for c in json.dumps({k: v for k, v in case.items() if k != 'name'}, separators=(',', ':'), ensure_ascii=False))


def run_bend(cmd, cases):
    results = []
    for start_index in range(0, len(cases), 24):
        chunk = cases[start_index:start_index + 24]
        run = subprocess.run(cmd + [encode(c) for c in chunk], cwd=ROOT, capture_output=True, text=True, timeout=1800, env={k: v for k, v in os.environ.items() if k != 'PI_CACHE_RETENTION'})
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
    parser.add_argument('--write-bodies', action='store_true')
    arguments = parser.parse_args()
    bodies = ROOT / 'packages/ai/test/anthropic-sse-bodies.bend'
    if arguments.write_bodies:
        bodies.write_text(named_suite_bodies())
    assert bodies.read_text() == named_suite_bodies(), 'anthropic-sse-bodies.bend is stale; run with --write-bodies'
    prefix = str(ROOT / 'build/anthropic')
    if not arguments.no_build:
        if not arguments.skip_suites:
            build(SUITES, prefix + '-suites', arguments.backends)
        build(DIFF, prefix + '-differential', arguments.backends)
    expected = []
    for suite, spec in NAMED.items():
        expected += ['PASS ' + name for name in upstream_names(suite, spec)]
    cases = [c for c in payload_cases() + request_cases() + response_cases() if arguments.only in c['name']]
    oracle = json.loads(subprocess.check_output(['bun', 'tests/anthropic_messages_reference.ts'], input=json.dumps({'cases': cases}), text=True, cwd=ROOT, env={k: v for k, v in os.environ.items() if k != 'PI_CACHE_RETENTION'}))
    failures = 0
    for backend in arguments.backends:
        if not arguments.skip_suites and not arguments.only:
            output = subprocess.run(command(prefix + '-suites', backend), cwd=ROOT, capture_output=True, text=True, timeout=3600)
            lines = output.stdout.splitlines()
            if output.returncode != 0 or lines != expected:
                failures += 1
                missing = [name for name in expected if name not in lines]
                print(f'FAIL {backend} named suites: exit {output.returncode}, missing {missing[:5]}, extra {[l for l in lines if l not in expected][:5]}, stderr {output.stderr[-500:]}')
            else:
                print(f'{backend}: {len(lines)} named upstream Anthropic tests pass')
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
