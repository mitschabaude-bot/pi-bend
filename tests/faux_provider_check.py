#!/usr/bin/env python3
"""faux-provider.test.ts versus pinned pi-mono.

Runs the ported named suite (every upstream test name except "unregisters the
provider", which needs upstream's dynamic api registry; the port dispatches
provider APIs statically), then compares usage estimates and chunking against
upstream's createFauxCore (tests/faux_provider_reference.ts). The split case
cuts a surrogate pair between two text deltas; the Bun backend cannot hold a
lone surrogate, so it runs on native backends only.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/ai/test/faux-provider.bend'
PENDING = {'unregisters the provider'}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/faux-provider')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
arguments = parser.parse_args()

source = (UPSTREAM / 'packages/ai/test/faux-provider.test.ts').read_text()
names = re.findall(r'^\tit\("([^"]+)"', source, re.M)
wanted = [name for name in names if name not in PENDING]
reference = subprocess.run(['bun', 'tests/faux_provider_reference.ts'], cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
estimates = [line for line in reference if line.startswith('D ')]
split = [line for line in reference if line.startswith(('S ', 'J '))]

if not arguments.no_build:
    if 'bun' in arguments.backends:
        subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
    if any(b.startswith('native') for b in arguments.backends):
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)

failures = 0
def lines(command):
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    return run.returncode, run.stdout.splitlines(), run.stderr

for backend in arguments.backends:
    command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
    code, out, err = lines(command)
    passed = [line[5:] for line in out if line.startswith('PASS ')]
    if code != 0 or passed != wanted:
        failures += 1
        print(f'FAIL {backend} named suite: missing {sorted(set(wanted) - set(passed))}; {"; ".join(l for l in out if not l.startswith("PASS "))[-800:]} {err[-800:]}')
    else:
        print(f'{backend}: {len(passed)} of {len(names)} upstream faux-provider tests pass (pending: {", ".join(sorted(PENDING))})')
    code, out, err = lines(command + ['diff'])
    got = [line for line in out if line.startswith('D ')]
    if code != 0 or got != estimates:
        failures += 1
        print(f'FAIL {backend} usage estimates: {got} != upstream {estimates} {err[-400:]}')
    else:
        print(f'{backend}: {len(got)} usage-estimate cases match pinned pi-mono')
    if backend == 'bun':
        continue
    code, out, err = lines(command + ['split'])
    if code != 0 or out != split:
        failures += 1
        print(f'FAIL {backend} split chunks: {out} != upstream {split} {err[-400:]}')
    else:
        print(f'{backend}: mid-pair chunking matches pinned pi-mono ({split[0]})')
sys.exit(1 if failures else 0)
