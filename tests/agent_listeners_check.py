#!/usr/bin/env python3
from upstream_pin import check_sibling
check_sibling()
import json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_listeners_reference.mts'],cwd=root,text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==8
lines=['import Base','import ../packages/agent/test/agent-listeners.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for mode,trace in enumerate(expected):lines.append(f'    T.scenario({mode}, {json.dumps(trace)})')
lines.append('    IO.print("PASS 8 live awaited-subscription source scenarios")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-listeners-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-listeners-check.bend','build/agent-listeners-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-listeners-check','--threads',str(threads)],cwd=root,check=True,timeout=120)
