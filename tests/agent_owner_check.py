#!/usr/bin/env python3
"""Compare the Agent owner with actual pinned Agent and loop execution."""
from upstream_pin import UPSTREAM
import json
import re
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
source = (UPSTREAM / 'packages/agent/src/agent.ts').read_text()
source_options = source.split('export interface AgentOptions {', 1)[1].split('\n}', 1)[0]
expected_fields = re.findall(r'^\t(\w+)\??:', source_options, re.M)
native = (root / 'packages/agent/src/agent.bend').read_text()
native_options = re.search(r'^  AgentOptions\{([^\n]+)\}', native, re.M).group(1)
actual_fields = re.findall(r'(?:^|, )(\w+):', native_options)
assert actual_fields == expected_fields, (actual_fields, expected_fields)
# Public mutable configuration fields have explicit native accessors.
public_fields = re.findall(r'^\tpublic (\w+)\??:', source.split('export class Agent {', 1)[1], re.M)
agent_module = (root / 'packages/agent/src/agent.bend').read_text()
for field in public_fields:
    for prefix in ('get', 'set'):
        accessor = prefix + field[0].upper() + field[1:]
        assert re.search(r'^def ' + accessor + r'\(', agent_module, re.M), accessor
expected = json.loads(subprocess.check_output(['node', 'tests/agent_run_reference.mts'], cwd=root, text=True))
assert len(expected) == 10
lines = ['import Base', 'import ../packages/agent/test/agent-owner.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for mode, value in enumerate(expected):
    lines.append(f'    T.scenario({mode}, {json.dumps(value)})')
lines.append('    IO.print("PASS 10 Agent owner source comparisons, constructor defaults and borrowed ownership")')
source = root / 'build/agent-owner-check.bend'
source.write_text('\n'.join(lines) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(source), 'build/agent-owner-check'], cwd=root, check=True)
for threads in ['1', '4']:
    subprocess.run(['build/agent-owner-check', '--threads', threads], cwd=root, check=True, timeout=120)
