"""Native provider preparation versus the pinned upstream wrapper and converters.

Python assembles inputs and orchestrates binaries; all preparation runs in Bend.
The oracle executes the actual pre-hook wrapper block with a recording SDK
constructor, so it performs no network requests and uses only fixture secrets.
"""
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from upstream_pin import PIN

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ['supportsDeveloperRole', 'supportsMidConvoSystemMessages', 'sessionAffinityFormat', 'supportsLongCacheRetention', 'supportsStrictMode', 'supportsOpenAIGrammarTools', 'supportsAdditionalTools', 'supportsToolSearch', 'supportsExplicitPromptCacheMode', 'supportsMaxOutputTokens']
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT.parent / 'pi-mono', text=True).strip() == PIN

def tool(name, grammar=False):
    value = dict(name=name, description='A tool', parameters={'type': 'object', 'properties': {'input': {'type': 'string'}}, 'required': ['input']})
    if grammar:
        value['constrainedSampling'] = {'type': 'grammar', 'variants': {'openai_lark': 'start: /[a-z]+/'}}
    return value

def case(mode, flags, scenario, provider):
    system = dict(role='system', content='initial', timestamp=1)
    if mode:
        system['toolsAdded'] = [tool('tool', mode == 5)]
    messages = [system, dict(role='user', content='hello', timestamp=1)]
    if mode == 2:
        messages.extend([dict(role='system', content='updated', toolsAdded=[tool('later')], timestamp=2), dict(role='user', content='again', timestamp=3)])
    if mode == 3:
        messages.append(dict(role='system', content='updated', toolsRemoved=[{'name': 'tool'}], timestamp=2))
    if mode == 4:
        changed = tool('tool'); changed['description'] = 'Redefined'
        messages.append(dict(role='system', content='updated', toolsAdded=[changed], timestamp=2))
    compat = dict(zip(['supportsMidConvoSystemMessages', 'supportsAdditionalTools', 'supportsToolSearch', 'supportsStrictMode', 'supportsOpenAIGrammarTools'], flags))
    model = dict(id='target', api='openai-responses', provider=provider, baseUrl='https://example.test', reasoning=True, input=['text'], compat=compat, headers={'User-Agent': 'model-agent', 'authorization': 'model-only'})
    options = dict(maxTokens=1, temperature=0, serviceTier='priority', toolChoice='required', reasoningEffort='high', reasoningSummary='concise', sessionId='session', cacheRetention='long', env={'PI_CACHE_RETENTION': 'long'})
    if scenario not in [1, 2, 3, 4, 5]: options['apiKey'] = 'fixture-key'
    if scenario == 2: options['headers'] = {'Authorization': 'Bearer custom'}
    if scenario == 3: options.update(apiKey='', headers={'CF-AIG-AUTHORIZATION': 'gateway'})
    if scenario == 5: options['headers'] = {'Authorization': ' \t'}
    if scenario == 6: options['headers'] = {'User-Agent': 'caller-agent', 'session_id': None, 'x-client-request-id': 'override'}
    if scenario == 7: options['cacheRetention'] = 'none'
    if scenario in [8, 10]: del options['cacheRetention']
    if scenario == 9: options['cacheRetention'] = 'short'
    if scenario == 10: del options['env']
    if scenario >= 11: options['serviceTier'] = [None, 'auto', 'default', 'flex', 'scale'][scenario - 11]
    encoded_flags = '.'.join('-' if f not in compat else str(int(compat[f])) for f in FIELDS)
    return dict(model=model, messages=messages, options=options), [str(mode), encoded_flags, str(scenario), provider]

specs = [(m, flags, 0, 'openai') for m in range(6) for flags in itertools.product([False, True], repeat=5)]
specs += [(m, (False, False, False, False, grammar), s, p) for m, grammar, s, p in itertools.product([0, 5], [False, True], range(1, 16), ['openai', 'openrouter', 'github-copilot'])]
pairs = [case(*spec) for spec in specs]
cases, arguments = zip(*pairs)
env = dict(os.environ, PI_CACHE_RETENTION='long')
expected = json.loads(subprocess.check_output(['node', 'tests/responses_prepare_reference.mts'], input=json.dumps(cases), text=True, cwd=ROOT, env=env))
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '26', '--stats', 'build/responses-prepare-build.json', '--', 'sh', 'scripts/build-pure.sh', 'packages/ai/test/openai-responses-prepare.bend', 'build/responses-prepare'], cwd=ROOT, check=True)

def encode(value):
    return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=True, separators=(',', ':')))

runs = []
backends = [('native-1', [str(ROOT/'build/responses-prepare'), '--threads', '1']), ('native-4', [str(ROOT/'build/responses-prepare'), '--threads', '4'])]
if '--js' in sys.argv:
    backends.append(('bun', [str(Path.home()/'.bun/bin/bun'), str(ROOT/'build/responses-prepare.js')]))
for label, command in backends:
    for start in range(0, len(cases), 8):
        argv = []
        for args, result in zip(arguments[start:start+8], expected[start:start+8]): argv.extend([*args, encode(result)])
        run = subprocess.run([*command, *argv], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        assert run.returncode == 0, (label, start, cases[start:start+8], expected[start:start+8], run.stdout, run.stderr)
    runs.append({'backend': label, 'cases': len(cases)})
    print(f'PASS {len(cases)} Responses preparation comparisons on {label}', flush=True)

pending = [ROOT/'packages/ai/test/openai-responses-prepare.bend']
visited = set()
while pending:
    path = pending.pop().resolve()
    if path in visited: continue
    visited.add(path)
    pending.extend(path.parent / relative for relative in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE))
visited.update([ROOT/'tests/responses_prepare_reference.mts', Path(__file__).resolve()])
record = {'upstream': PIN, 'runs': runs, 'cases': cases, 'expected': expected, 'sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(visited)}}
record['artifacts'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'build/responses-prepare.c', ROOT/'build/responses-prepare', *([ROOT/'build/responses-prepare.js'] if '--js' in sys.argv else [])]}
(ROOT/'build/responses-prepare-results.json').write_text(json.dumps(record, indent=2) + '\n')
