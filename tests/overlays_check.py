"""Compare immutable overlay focus transitions with pinned TuiBase source."""
import json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
r=random.Random(93411)
cases=[]
for i in range(180):
 steps=[dict(op='focus',target=1,mounted=[1,2,3])];live=[];next_id=1
 for j in range(55):
  op=r.choice(['show','focus','hide','pop','hidden','visible','focusOverlay','unfocus','input','input'])
  if not live and op not in ['show','focus','input']:op='show'
  s=dict(op=op)
  if op=='show':
   s.update(component=r.randrange(10,15),passive=r.choice([True,False]),visible=r.choice([True,True,False]));live.append(next_id);next_id+=1
  elif op=='focus':s.update(target=r.choice([None,1,2,3,10,11,12]))
  elif op=='hide':s['handle']=r.choice(live);live.remove(s['handle'])
  elif op=='pop':live.pop()
  elif op in ['hidden','visible','focusOverlay','unfocus']:
   s['handle']=r.choice(live)
   if op in ['hidden','visible']:s['value']=r.choice([True,False])
   elif op=='unfocus' and r.choice([True,False]):s['target']=r.choice([None,1,2,3,10,11])
  if r.randrange(9)==0:s['mounted']=r.choice([[],[1],[2,3],[1,2,3]])
  steps.append(s)
 cases.append(steps)
# Retiring a hidden overlay makes all subsequent handle operations inert.
retired=[dict(op='focus',target=1),dict(op='show',component=10),dict(op='hidden',handle=1,value=True),dict(op='hide',handle=1)]
command=sys.argv[1:] or ['bun','build/overlays.js']
def execute(command,values):
 p=subprocess.run(command+[json.dumps(values,separators=(',',':'))],cwd=ROOT,capture_output=True,text=True,timeout=120)
 assert p.returncode==0,(command,p.returncode,p.stderr[-4000:])
 value=json.loads(p.stdout);assert len(value)==len(values);return value
for start in range(0,len(cases),4):
 group=cases[start:start+4];expected=execute(['bun','tests/overlays_reference.ts'],group);actual=execute(command,group)
 for i,(a,b) in enumerate(zip(actual,expected)):
  for j,(x,y) in enumerate(zip(a,b)):
   assert x==y,(start+i,j,group[i][:j+1],x,y)
  assert len(a)==len(b)
base=execute(command,[retired])[0][-1]
for operation in [dict(op='hidden',handle=1,value=False),dict(op='focusOverlay',handle=1),dict(op='unfocus',handle=1,target=2),dict(op='hide',handle=1)]:
 value=execute(command,[retired+[operation]])[0][-1]
 assert value==dict(base,calls=[],hide=False,render=False),(operation,value,base)
print(f'{len(cases)} sequences / {sum(map(len,cases))} exact source focus transitions; four retired-handle no-op corrections pass')
