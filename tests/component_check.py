"""Compare immutable native container traces to the pinned upstream implementation."""
import argparse,itertools,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--prefix',type=Path,default=ROOT/'build/component');p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
def run(command,values):
 r=subprocess.run(command+[json.dumps(values)],cwd=ROOT,text=True,capture_output=True,timeout=60)
 assert r.returncode==0,(r.returncode,r.stderr[-2000:]);return json.loads(r.stdout)
def event(**kw):return dict(type='press',button='left',wheelDelta=None,clickCount=None,x=2,y=0,screenX=12,screenY=20,width=10,height=20,shift=False,alt=False,ctrl=False,**{})|kw
def mouse(**kw):return dict(op='mouse',event=event(**kw))
responses=[None,{},*({'handled':h,'capture':c,'focus':f,'render':r} for h,c,f,r in itertools.product([False,True],[False,True],[False,True],[None,False,True])),dict(forward=True,target=dict(component=77,originX=-4,originY=30,width=3,height=2),focusTarget=78,capture=True,focus=True,render=False)]
cases=[]
for response in responses:
 for delegates in [False,True]:
  children=[dict(id=1,height=2,response=response),dict(id=2,height=0,response=response),dict(id=3,height=3,response=response)]
  steps=[dict(op='add',id=i) for i in [1,2,3]]
  steps += [dict(op='mouse',delegates=delegates,event=event(y=y,screenY=40+y)) for y in [-2,0,1,2,4,5,20]]
  steps += [dict(op='render',width=10)]
  steps += [dict(op='mouse',delegates=delegates,event=event(y=y,x=-3,screenX=-20)) for y in [0,1,2,4]]
  cases.append(dict(children=children,steps=steps))
# Last displayed layout survives add/remove/clear/invalidate until next render;
# width mismatches measure all current children without replacing that cache.
children=[dict(id=i,height=i-1,variable=True,response={'capture':True,'focus':True}) for i in [1,2,3]]
steps=[dict(op='add',id=i) for i in [1,2,1,3]]+[dict(op='render',width=10),dict(op='remove',id=1),dict(op='invalidate'),mouse(y=0),mouse(y=3,width=11),mouse(y=3),dict(op='clear'),mouse(y=0),mouse(y=0,width=11),dict(op='render',width=10),mouse(y=0)]
cases.append(dict(children=children,steps=steps))
rng=random.Random(77651)
for _ in range(100):
 children=[dict(id=i,height=rng.randrange(4),variable=bool(rng.randrange(2)),response=rng.choice(responses)) for i in range(1,5)]
 steps=[]
 for j in range(30):
  op=rng.choice(['add','add','remove','clear','render','invalidate','mouse','mouse'])
  steps.append(dict(op=op,id=rng.randrange(1,6),width=rng.randrange(0,15),delegates=bool(rng.randrange(2)),event=event(y=rng.randrange(-3,15),height=rng.randrange(0,12),width=rng.randrange(0,15))))
 cases.append(dict(children=children,steps=steps))
for _ in range(100):
 t=dict(component=7,originX=rng.randrange(-50,51),originY=rng.randrange(-50,51),width=rng.randrange(30),height=rng.randrange(30))
 e=event(type=rng.choice(['press','release','move','drag','click','wheel']),button=rng.choice(['left','middle','right','none']),wheelDelta=rng.choice([None,-10,0,5]),clickCount=rng.choice([None,1,2,3]),screenX=rng.randrange(-50,51),screenY=rng.randrange(-50,51),shift=True,alt=True,ctrl=True)
 cases.append(dict(children=[],steps=[dict(op='retarget',target=t,event=e)]))
expected=[]
for i in range(0,len(cases),10):expected.extend(run(['bun','tests/component_reference.ts'],cases[i:i+10]))
for backend in a.backends:
 cmd=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 for i in range(0,len(cases),10):
  got=run(cmd,cases[i:i+10])
  for case,actual,want in zip(cases[i:i+10],got,expected[i:i+10]):assert actual==want,(backend,case,actual,want)
 print(f'{backend}: {len(cases)} component/container traces match upstream',flush=True)
