#!/usr/bin/env python3
"""Composed state/queue/lifecycle comparisons against the pinned Agent."""
from upstream_pin import check_sibling
check_sibling()
import itertools,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
ops=[4,5,1,1,2,7,4,4,0,9,10,5,4,5,4,5,0,8,0,3,6,7,11,9,10,1,2,0,5,0,4,3,10,5,1,1,2,12,17,2,13,18,1,2,14,15,1,2,16]
fixtures=[dict(history=h,steering=s,follow=f,ops=ops) for h,s,f in itertools.product(range(3),range(2),range(2))]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_runtime_reference.mts'],cwd=root,input=json.dumps(fixtures),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected)==len(fixtures)
lines=['import Base','import ../packages/agent/test/agent-runtime.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for f,trace in zip(fixtures,expected):
    assert len(trace)==len(ops)
    ops_bend=' <> '.join(map(str,ops))+' <> Nil{}'
    expected_bend=' <> '.join(map(json.dumps,trace))+' <> Nil{}'
    lines.append(f'    T.scenario({f["history"]}, {f["steering"]}, {f["follow"]}, {ops_bend}, {expected_bend})')
lines.append(f'    IO.print("PASS {len(fixtures)*len(ops)} composed Agent runtime source snapshots")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-runtime-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-runtime-check.bend','build/agent-runtime-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-runtime-check','--threads',str(threads)],cwd=root,check=True,timeout=120)
