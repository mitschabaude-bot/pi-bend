"""Pinned SettingsList assertions, state transitions, rendering and callback contracts."""
from upstream_pin import UPSTREAM
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/settings-list')
a=p.parse_args(); E='\x1b'; rng=random.Random(991)
oracle=['bun','tests/settings_list_reference.ts',str(UPSTREAM),'build/input-reference/node_modules']
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-4000:])
 result=json.loads(r.stdout);assert len(result)==len(values)
 return result
def batches(command,values):
 out=[]
 for i in range(0,len(values),8):out.extend(run(command,values[i:i+8]))
 return out
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
items=[dict(id=str(i),label=label,currentValue='yes',values=['yes','no','auto'],description='Details for '+label) for i,label in enumerate(['Alpha option','Beta option','Gamma entry','Delta setting','One more','Last option'])]
cases=[]
for i in range(100):
 steps=[]
 for j in range(25):
  op=rng.randrange(7)
  if op<3:steps.append(dict(op='input',data=rng.choice(['a',' ','zz','\x7f','\r',E,E+'[A',E+'[B',E+'b','\x15',E+'[97u'])))
  elif op==3:steps.append(dict(op='render',width=rng.choice([0,1,2,4,8,15,40,80])))
  elif op==4:steps.append(dict(op='mouse',event=dict(type=rng.choice(['press','click','wheel','move']),button=rng.choice(['left','right']),x=3,y=rng.randrange(-2,10),wheelDelta=rng.choice([-2,0,2]))))
  elif op==5:steps.append(dict(op='select',id=str(rng.randrange(8))))
  else:steps.append(dict(op='update',id=str(rng.randrange(8)),value=rng.choice(['missing','yes','no'])))
 cases.append(dict(items=items if i%9 else [],maxVisible=rng.choice([0,1,3,5,10]),options=dict(enableSearch=i%2==0),steps=steps,styled=i%3==0,kitty=i%2==1,bindings={'tui.select.down':'ctrl+j'} if i%7==0 else {}))
for width in [0,1,2,3,4,5,8,20,40,80]:
 cases.append(dict(items=[dict(id='a',label='界'*40,currentValue='é👩‍💻',description='long words that wrap\nnext line'),dict(id='b',label='short',currentValue='value')],cursor='界> ',steps=[dict(op='render',width=width),dict(op='input',data=E+'[B'),dict(op='render',width=width)]))
for mode in ['none','unhandled','capture','normal']:
 children=[dict(id='a',label='First',currentValue='one',submenu=dict(mouse=mode)),dict(id='b',label='Second',currentValue='two',submenu=dict(mouse=mode)),dict(id='c',label='Third',currentValue='x',values=['x','y'])]
 steps=[dict(op='input',data='\r'),dict(op='render',width=20),dict(op='invalidate'),dict(op='mouse',event=dict(type='press',button='left',x=2,y=3)),dict(op='input',data='save'),dict(op='input',data='\r'),dict(op='input',data='goto:b'),dict(op='render',width=8),dict(op='complete',origin=0,value='retained',navigateTo='c'),dict(op='render',width=30),dict(op='select',id='a'),dict(op='input',data='\r'),dict(op='input',data='cancel'),dict(op='render',width=40)]
 cases.append(dict(items=children,steps=steps))
# Missing navigate target re-activates the current item; retained completion keeps its own origin id.
cases.append(dict(items=[dict(id='a',label='A',currentValue='v',submenu={})],steps=[dict(op='input',data='\r'),dict(op='complete',origin=0,value='',navigateTo='missing'),dict(op='complete',origin=0),dict(op='render',width=10)]))
prepared=batches(oracle,cases); all_cases=original+prepared
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 actual=batches(command,[case['input'] for case in all_cases])
 for index,(case,value) in enumerate(zip(all_cases,actual)):
  if value!=case['expected']:
   Path('/tmp/settings-list-failure.json').write_text(json.dumps(dict(index=index,case=case,actual=value),ensure_ascii=False,indent=2))
   raise AssertionError((backend,index,case.get('name'),'see /tmp/settings-list-failure.json'))
 print(f'{backend}: {len(original)} original SettingsList tests and {len(prepared)} render/search/mouse/submenu/callback sequences passed',flush=True)
