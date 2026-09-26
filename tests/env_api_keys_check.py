#!/usr/bin/env python3
"""env-api-keys.ts versus pinned pi-mono: the named suite, then findEnvKeys and
getEnvApiKey for every provider upstream knows under several environments.

The environments are passed as the provider env; the process environment must
not define provider credentials (the check removes them before running both
sides). Ambient Vertex ADC detection depends on the machine's gcloud file, so
the Vertex cases use an explicit GOOGLE_APPLICATION_CREDENTIALS path.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/env-api-keys.bend'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/env-api-keys')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
arguments = parser.parse_args()

source = (UPSTREAM / 'packages/ai/src/env-api-keys.ts').read_text()
import re
names = sorted(set(re.findall(r'"([A-Z][A-Z0-9_]+)"', source)))
providers = sorted(set(re.findall(r'^\t\t"?([a-z][a-z0-9-]*)"?: "', source, re.M)) | {'github-copilot', 'anthropic', 'google-vertex', 'amazon-bedrock', 'unknown-provider'})
clean = {k: v for k, v in os.environ.items() if k not in names and not k.startswith(('AWS_', 'GOOGLE_', 'GCLOUD_'))}
existing = str(ROOT / 'package.json') if (ROOT / 'package.json').exists() else str(Path(__file__).resolve())
envs = [
    {},
    {name: f'v-{name}' for name in names if name != 'GOOGLE_APPLICATION_CREDENTIALS'},
    {'ANTHROPIC_AUTH_TOKEN': 'a'},
    {'ANTHROPIC_AUTH_TOKEN': 'a', 'ANTHROPIC_API_KEY': 'k'},
    {'GOOGLE_APPLICATION_CREDENTIALS': existing, 'GOOGLE_CLOUD_PROJECT': 'p', 'GOOGLE_CLOUD_LOCATION': 'l'},
    {'GOOGLE_APPLICATION_CREDENTIALS': '/nonexistent/adc.json', 'GCLOUD_PROJECT': 'p', 'GOOGLE_CLOUD_LOCATION': 'l'},
    {'AWS_ACCESS_KEY_ID': 'i'},
    {'AWS_ACCESS_KEY_ID': 'i', 'AWS_SECRET_ACCESS_KEY': 's'},
    {'AWS_WEB_IDENTITY_TOKEN_FILE': '/token'},
    {'OPENAI_API_KEY': ''},
]
cases = [(provider, env) for provider in providers for env in envs]
script = f'''
const {{ findEnvKeys, getEnvApiKey }} = await import({json.dumps(str(UPSTREAM / 'packages/ai/src/env-api-keys.ts'))});
await new Promise((r) => setTimeout(r, 50));
const cases = JSON.parse(await new Response(Bun.stdin.stream()).text());
const out = cases.map(([p, env]) => {{
  const keys = findEnvKeys(p, env);
  const key = getEnvApiKey(p, env);
  return `D ${{p}}|${{keys ? "[" + keys.join(",") + "]" : "undefined"}}|${{key ?? "undefined"}}`;
}});
console.log(out.join("\\n"));
'''
expected = subprocess.run(['bun', '-e', script], input=json.dumps(cases), capture_output=True, text=True, env=clean, check=True).stdout.split('\n')
expected = [line for line in expected if line.startswith('D ')]
assert len(expected) == len(cases), (len(expected), len(cases))

if not arguments.no_build:
    if 'bun' in arguments.backends:
        subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
    if any(b.startswith('native') for b in arguments.backends):
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)

failures = 0
for backend in arguments.backends:
    command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
    named = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env=clean)
    passed = [line for line in named.stdout.splitlines() if line.startswith('PASS ')]
    if named.returncode != 0 or len(passed) != 7:
        failures += 1
        print(f'FAIL {backend} named suite: {named.stdout[-800:]} {named.stderr[-800:]}')
    else:
        print(f'{backend}: 7 named upstream env-api-keys tests pass')
    got = []
    for start in range(0, len(cases), 200):
        chunk = cases[start:start + 200]
        run = subprocess.run(command + [p + '|' + ';'.join(f'{k}={v}' for k, v in env.items()) for p, env in chunk], cwd=ROOT, capture_output=True, text=True, env=clean)
        assert run.returncode == 0, run.stderr[-2000:]
        got += [line for line in run.stdout.splitlines() if line.startswith('D ')]
    mismatches = [(c, w, g) for c, w, g in zip(cases, expected, got) if w != g]
    for case, want, have in mismatches[:8]:
        print(f'FAIL {backend} {case}: native {have} != upstream {want}')
    failures += bool(mismatches) or len(got) != len(cases)
    print(f'{backend}: {len(cases) - len(mismatches)} of {len(cases)} findEnvKeys/getEnvApiKey cases match pinned pi-mono')
sys.exit(1 if failures else 0)
