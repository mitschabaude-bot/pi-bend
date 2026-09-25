"""Native OpenAI header assembly against SDK 6.40.0's actual methods.

Metadata is injected at the platform-identity boundary. No network requests or
real credentials are involved. Python is only the fixture/build orchestrator.
"""
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
SDK_FILES = ['package.json', 'src/client.ts', 'src/internal/headers.ts', 'src/internal/utils/values.ts']
SDK_HASHES = {name: hashlib.sha256((SDK/name).read_bytes()).hexdigest() for name in SDK_FILES}
CASES = []

def add(**settings):
    case = dict(userAgent='pi-bend-fixture', platform={'X-Stainless-Lang': 'bend', 'X-Stainless-Runtime': 'native'}, apiKey='fixture-key', retryCount=0)
    case.update(settings)
    for key in ['client', 'body', 'request']:
        if key in case:
            assert isinstance(case[key], dict) and all(isinstance(n, str) and (v is None or isinstance(v, str)) for n, v in case[key].items())
    assert all(isinstance(n, str) and isinstance(v, str) for n, v in case['platform'].items())
    CASES.append(case)

auth = [{}, {'Authorization': None}, {'Authorization': ''}, {'Authorization': ' \t '}, {'Authorization': 'custom'}, {'Authorization': '', 'api-key': 'other'}, {'Authorization': '', 'api-key': None}, {'AUTHORIZATION': None, 'authorization': 'again'}]
for client, request, timeout in itertools.product(auth, auth, [0, 1, 1501, 600000]):
    add(client=client, request=request, timeout=timeout, body={'Content-Type': 'application/json'})
for timeout, retry in itertools.product([None, -0.0, 999, 1000, 1001, 600001, -1, 0.5, 1.5, 1e20, 1e100], [0, 3]):
    add(**({} if timeout is None else {'timeout': timeout}), retryCount=retry, organization='organization', project='project')
for name, value, location in itertools.product(['X-Test', 'AUTHORIZATION', 'Content-Type', 'User-Agent'], [None, '', ' \t value \t ', 'café', '\xff', '\u0100', 'a\nb', '\x00', '\r\ntrimmed\r\n'], ['client', 'body', 'request']):
    add(**{location: {name: value}})
for name, value in itertools.product(['', 'bad name', 'bad:name', 'é'], [None, 'value']):
    add(client={name: value})
add(platform={'Accept': 'platform-type', 'X-Stainless-Timeout': 'platform-timeout', 'OpenAI-Organization': 'platform-org'})
add(client={'User-Agent': 'client-agent', 'Content-Type': 'client-type'}, body={'Content-Type': 'application/json'}, request={'USER-AGENT': None, 'content-type': 'request-type'})
add(client={'Authorization': None}, body={'authorization': 'reintroduced'}, request={'Authorization': ''})
add(apiKey='bad\nkey', request={'Authorization': 'later-valid'})
add(organization='bad\norg', client={'OpenAI-Organization': None})

raw = json.loads(subprocess.check_output(['node', 'tests/openai_request_headers_reference.mts'], input=json.dumps(CASES), text=True, cwd=ROOT))
expected = [{k: v for k, v in case.items() if k != 'diagnostic'} for case in raw]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '14', '--stats', 'build/openai-request-headers-build.json', '--', 'sh', 'scripts/build-pure.sh', 'packages/ai/test/openai-request-headers.bend', 'build/openai-request-headers'], cwd=ROOT, check=True)

def encode(value):
    return ','.join(str(ord(c)) for c in json.dumps(value, ensure_ascii=True, separators=(',', ':')))

backends = [('native-1', [str(ROOT/'build/openai-request-headers'), '--threads', '1']), ('native-4', [str(ROOT/'build/openai-request-headers'), '--threads', '4'])]
if '--js' in sys.argv:
    backends.append(('bun', [str(Path.home()/'.bun/bin/bun'), str(ROOT/'build/openai-request-headers.js')]))
runs = []
for name, command in backends:
    for start in range(0, len(CASES), 8):
        argv = []
        for case, result in zip(CASES[start:start+8], expected[start:start+8]):
            argv.extend([str(case['retryCount']), encode(case), encode(result)])
        run = subprocess.run([*command, *argv], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert run.returncode == 0, (name, start, CASES[start:start+8], expected[start:start+8], run.stdout, run.stderr)
    runs.append({'backend': name, 'cases': len(CASES), 'passed': True})
    print(f'PASS {len(CASES)} OpenAI header comparisons on {name}', flush=True)

pending = [ROOT/'packages/ai/test/openai-request-headers.bend']
visited = set()
while pending:
    path = pending.pop().resolve()
    if path in visited: continue
    visited.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE))
visited.update([ROOT/'tests/openai_request_headers_reference.mts', Path(__file__).resolve()])
assert SDK_HASHES == {name: hashlib.sha256((SDK/name).read_bytes()).hexdigest() for name in SDK_FILES}, 'SDK sources changed during validation'
record = {'sdk': '6.40.0', 'sdk_sha256': SDK_HASHES, 'scope': 'Actual SDK header/default/authentication methods; platform identity explicitly injected; error families compared with raw oracle diagnostics retained.', 'runs': runs, 'cases': CASES, 'reference': raw, 'sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(visited)}}
record['artifacts'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'build/openai-request-headers.c', ROOT/'build/openai-request-headers', *([ROOT/'build/openai-request-headers.js'] if '--js' in sys.argv else [])]}
(ROOT/'build/openai-request-headers-results.json').write_text(json.dumps(record, indent=2)+'\n')
