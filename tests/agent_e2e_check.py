#!/usr/bin/env python3
"""e2e.test.ts (packages/agent) versus pinned pi-mono.

Runs packages/agent/test/e2e.bend, the Agent against the faux provider, and
requires every upstream test name, in upstream order, to print PASS. The
faux core streams to the Agent directly instead of through a process-wide
api registry (see the suite's header).
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'packages/agent/test/e2e.bend'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', default='build/agent-e2e')
parser.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
parser.add_argument('--no-build', action='store_true')
arguments = parser.parse_args()

source = (UPSTREAM / 'packages/agent/test/e2e.test.ts').read_text()
names = re.findall(r'^\s*it\("([^"]+)"', source, re.M)
assert len(names) == 10, names

if not arguments.no_build:
    if 'bun' in arguments.backends:
        subprocess.run(['bun', 'build/bend-native-toolchain/bend2/main.ts', ENTRY, '-o', arguments.prefix + '.js'], cwd=ROOT, check=True)
    if any(b.startswith('native') for b in arguments.backends):
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', ENTRY, arguments.prefix], cwd=ROOT, check=True)

failures = 0
for backend in arguments.backends:
    command = ['bun', arguments.prefix + '.js'] if backend == 'bun' else [arguments.prefix, '--threads', backend[-1]]
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    out = run.stdout.splitlines()
    passed = [line[5:] for line in out if line.startswith('PASS ')]
    if run.returncode != 0 or passed != names:
        failures += 1
        print(f'FAIL {backend}: missing {[n for n in names if n not in passed]}; {"; ".join(l for l in out if not l.startswith("PASS "))[-800:]} {run.stderr[-800:]}')
    else:
        print(f'{backend}: {len(passed)} of {len(names)} upstream e2e tests pass')
sys.exit(1 if failures else 0)
