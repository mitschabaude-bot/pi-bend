#!/usr/bin/env python3
import itertools,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
fixtures=[dict(aborted=a,error=e,stage=s,listener=l) for a,e,s,l in itertools.product([False,True],['boom',''],range(5),range(2))]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_failure_reference.mts'],cwd=root,input=json.dumps(fixtures),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==len(fixtures)
lines=['import Base','import ../packages/agent/test/agent-failure.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for f,trace in zip(fixtures,expected):
    lines.append(f'    T.scenario({"True{}" if f["aborted"] else "False{}"}, {json.dumps(f["error"])}, {f["stage"]}, {f["listener"]}, {json.dumps(trace)})')
lines.append(f'    IO.print("PASS {len(fixtures)} Agent failure recovery source scenarios")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-failure-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-failure-check.bend','build/agent-failure-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-failure-check','--threads',str(threads)],cwd=root,check=True,timeout=120)
