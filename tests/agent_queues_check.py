#!/usr/bin/env python3
"""Source comparisons for pending queues and the Agent.continue decision boundary."""
import itertools
import json
import pathlib
import subprocess
root=pathlib.Path(__file__).resolve().parents[1]
queues=[dict(mode=mode,ops=list(ops)) for mode in [0,1] for ops in itertools.product(range(6),repeat=3)]
queues += [dict(mode=mode,ops=[0,1,2,0,1,5,2,4,2,3,0,2]) for mode in [0,1]]
continuations=[dict(active=active,history=history,steeringMode=steeringMode,followMode=followMode,steering=steering,follow=follow) for active,history,steeringMode,followMode,steering,follow in itertools.product([False,True],range(8),range(2),range(2),range(4),range(4))]
result=subprocess.run(['node','--experimental-strip-types','tests/agent_queues_reference.mts'],cwd=root,input=json.dumps(dict(queues=queues,continuations=continuations)),text=True,capture_output=True,check=True)
expected=json.loads(result.stdout)
assert len(expected['queues'])==len(queues) and len(expected['continuations'])==len(continuations)
calls=['    T.pairScenario()']
for fixture,trace in zip(queues,expected['queues']):
    assert len(trace)==len(fixture['ops'])+1
    ops=' <> '.join(map(str,fixture['ops']))+' <> Nil{}'
    values=' <> '.join(json.dumps(value) for value in trace)+' <> Nil{}'
    calls.append(f'    T.queueScenario({fixture["mode"]}, {ops}, {values})')
for fixture,value in zip(continuations,expected['continuations']):
    fields=['True{}' if fixture['active'] else 'False{}']+[str(fixture[key]) for key in ['history','steeringMode','followMode','steering','follow']]
    calls.append('    T.continuationScenario('+', '.join(fields+[json.dumps(value)])+')')
# Bound generated function depth so the compiler does not expand one enormous IO chain.
lines=['import Base','import ../packages/agent/test/agent-queues.bend as T']
batches=[calls[index:index+64] for index in range(0,len(calls),64)]
for index,batch in enumerate(batches):
    lines += [f'def batch{index}() -> IO(Unit):','  do IO<Unit>:',*batch]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']
lines += [f'    batch{index}()' for index in range(len(batches))]
count=sum(len(trace) for trace in expected['queues'])
lines.append(f'    IO.print("PASS {count} queue snapshots and {len(continuations)} continuation source comparisons")')
(root/'build').mkdir(exist_ok=True)
(root/'build/agent-queues-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-queues-check.bend','build/agent-queues-check'],cwd=root,check=True)
for threads in [1,4]:subprocess.run(['build/agent-queues-check','--threads',str(threads)],cwd=root,check=True,timeout=120)
