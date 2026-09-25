#!/usr/bin/env python3
"""Compare native state transitions with pinned Agent initialization/processEvents."""
from upstream_pin import check_sibling
check_sibling()
import json
import pathlib
import subprocess
root=pathlib.Path(__file__).resolve().parents[1]
modes=list(range(7))
result=subprocess.run(['node','--experimental-strip-types','tests/agent_state_reference.mts'],cwd=root,input=json.dumps(modes),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==7 and all(len(v)==23 for v in expected)
lines=['import Base','import ../packages/agent/test/agent-state.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for mode,states in zip(modes,expected):
    values=' <> '.join(json.dumps(v) for v in states)+' <> Nil{}'
    lines.append(f'    T.scenario({mode}, {values})')
lines.append('    IO.print("PASS 161 Agent initialization/lifecycle/event state comparisons")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-state-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-state-check.bend','build/agent-state-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-state-check','--threads',str(threads)],cwd=root,check=True,timeout=120)
