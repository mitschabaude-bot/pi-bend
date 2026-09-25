"""Replay editing-history traces against actual pinned KillRing/UndoStack."""
import argparse,json,random,subprocess
from pathlib import Path
from upstream_pin import PIN, UPSTREAM
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('command',nargs=argparse.REMAINDER);args=p.parse_args();command=args.command
if command[:1]==['--']:command=command[1:]
assert command
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=UPSTREAM,text=True).strip()==PIN
traces=[[],[{'op':'pop'},{'op':'clear'},{'op':'rotate'}]]
for prepend in [False,True]:
 for accumulate in [False,True]:
  traces.append([{'op':'kill','text':text,'prepend':prepend,'accumulate':accumulate} for text in ['','one','two','','三\n😀']]+[{'op':'rotate'}]*7+[{'op':'kill','text':'after rotation','accumulate':True,'prepend':prepend}])
traces.append([{'op':'push','text':'original'},{'op':'save'},{'op':'push','text':'changed'},{'op':'pop'},{'op':'clear'},{'op':'restore'},{'op':'pop'},{'op':'pop'}])
rng=random.Random(19273)
for _ in range(150):
 ops=[]
 for _ in range(100):
  kind=rng.choice(['kill','kill','rotate','push','push','pop','clear','save','restore'])
  ops.append({'op':kind,'text':rng.choice(['','a',' b','\n','\t','😀','e\u0301','中文','one\ntwo']), 'prepend':bool(rng.randrange(2)),'accumulate':bool(rng.randrange(2))})
 traces.append(ops)
# Longer accumulation, repeated rotation, and stack retirement without a size cap.
traces.append([{'op':'kill','text':'x'} for _ in range(500)]+[{'op':'rotate'} for _ in range(1001)])
traces.append([{'op':'push','text':str(i)} for i in range(2000)]+[{'op':'pop'} for _ in range(2001)])
expected=json.loads(subprocess.check_output(['bun','tests/editor_history_reference.ts'],input=json.dumps(traces),text=True,cwd=ROOT))
for i,trace in enumerate(traces):
 actual=json.loads(subprocess.check_output(command+[json.dumps(trace,separators=(',',':'))],text=True,cwd=ROOT))
 assert actual==expected[i],(i,next((j for j,(a,b) in enumerate(zip(actual,expected[i])) if a!=b),None))
print(f'{len(traces)} traces / {sum(map(len,traces))} state transitions match pinned upstream')
