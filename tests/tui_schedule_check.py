"""Compare TuiBase scheduling transitions with hash-pinned upstream methods."""
import json, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
oracle=['bun',str(root/'tests/tui_schedule_reference.ts'),str(root.parent/'pi-mono')]
cases=[
 'rq', 'rqt', 'rrqtrqt', 'rfrqq', 'rqftq', 'rqfq',
 'rqnq', 'rqnqt', 'fqi', 'ffqq', 'rfqq', 'irqq',
 'xfrqq', 'rqtfrqq', 'rqtNq', 'rqnfrq',
]
def run(command,actions):
 p=subprocess.run(command+[actions],cwd=root,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(command,actions,p.stderr[-2000:])
 return p.stdout
for backend in ['bun','native-1','native-4']:
 for actions in cases:
  expected=json.loads(run(oracle,actions))
  command=['bun',str(root/'build/tui-schedule.js')] if backend=='bun' else [str(root/'build/tui-schedule'),'--threads',backend[-1]]
  actual=run(command,actions).strip().splitlines()
  assert actual==expected,(backend,actions,actual,expected)
 print(f'{backend}: {len(cases)} exact source scheduling traces passed')
# Upstream start() explicitly calls requestRender(); the current Bend
# StartRendering transition only clears stopped, leaving the queue empty.
expected=json.loads(run(oracle,'b'))
for backend in ['bun','native-1','native-4']:
 command=['bun',str(root/'build/tui-schedule.js')] if backend=='bun' else [str(root/'build/tui-schedule'),'--threads',backend[-1]]
 actual=run(command,'b').strip().splitlines()
 assert expected!=actual and expected[0].endswith('|s,') and actual[0].endswith('|'),(backend,expected,actual)
print('known gap: StartRendering misses start() requestRender queue')
