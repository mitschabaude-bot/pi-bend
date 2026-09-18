#!/usr/bin/env python3
"""Compare the composed Agent run with actual pinned Agent and loop execution."""
import json
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
expected = json.loads(subprocess.check_output(['node', 'tests/agent_run_reference.mts'], cwd=root, text=True))
assert len(expected) == 10
lines = ['import Base', 'import ../packages/agent/test/agent-run.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for mode, value in enumerate(expected):
    lines.append(f'    T.scenario({mode}, {json.dumps(value)})')
lines.append('    IO.print("PASS 10 composed Agent/provider-loop source comparisons")')
source = root / 'build/agent-run-check.bend'
source.write_text('\n'.join(lines) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), 'build/agent-run-check'], cwd=root, check=True)
for threads in ['1', '4']:
    subprocess.run(['build/agent-run-check', '--threads', threads], cwd=root, check=True, timeout=120)
