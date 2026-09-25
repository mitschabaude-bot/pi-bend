"""Pinned SelectList source tests and exact rendering/callback/input comparisons."""
from upstream_pin import UPSTREAM
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/select-list')
p.add_argument('--reference',default=str(UPSTREAM))
p.add_argument('--modules',default='build/select-reference/node_modules')
a=p.parse_args(); E='\x1b'
oracle=['bun','tests/select_list_reference.ts',a.reference,a.modules]
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-3000:])
 result=json.loads(r.stdout)
 assert len(result)==len(values),(command,"result count",len(values),len(result))
 return result
def batches(command,values):
 out=[]
 for i in range(0,len(values),20):out.extend(run(command,values[i:i+20]))
 return out
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
rng=random.Random(722); cases=[]
items=[{'value':'Alpha','label':'alpha','description':' first\r\nsecond\n\nthird '},{'value':'beta','label':'','description':' '},{'value':'beta-long','label':'a very long primary label that requires truncation','description':'long detail'},{'value':'界','label':'界界界','description':' wide word '},{'value':'styled','label':E+'[31mred label'+E+'[39m','description':'colored text'},{'value':'other','label':'other'},{'value':'next','label':'next','description':''}]
for width in [0,1,2,3,4,10,40,41,42,60,80,100]:
 for maximum in [0,1,2,5,10]:
  for primary in ['', 'ellipsis','overflow']:
   case=dict(items=items,width=width,maxVisible=maximum,primary=primary,styled=rng.choice([False,True]),layout=rng.choice([{},dict(minPrimaryColumnWidth=12,maxPrimaryColumnWidth=20),dict(minPrimaryColumnWidth=50,maxPrimaryColumnWidth=15),dict(maxPrimaryColumnWidth=0),dict(minPrimaryColumnWidth=70)]))
   case['steps']=[{'op':'index','index':rng.choice([0,1,3,6,99])},{'op':'render','width':width}]
   cases.append(case)
# Independent snapshots check changes after every action and complete callback order.
keys=[E+'[A',E+'[B','\r',E,'\x03','j','k',E+'[5~',E+'[6~','x']
for n in range(35):
 steps=[]
 for i in range(35):
  choice=rng.randrange(5)
  if choice==0:steps.append({'op':'filter','filter':rng.choice(['','b','B','nomatch','a','界'])})
  elif choice==1:steps.append({'op':'input','data':rng.choice(keys)})
  elif choice==2:steps.append({'op':'index','index':rng.randrange(20)})
  elif choice==3:steps.append({'op':'render','width':rng.choice([0,3,41,80])})
  else:steps.append({'op':'mouse','event':dict(type=rng.choice(['press','click','wheel','move','drag','release']),button=rng.choice(['left','right','none']),y=rng.choice([-1,0,1,2,4,8]),wheelDelta=rng.choice([-5,-1,0,1,5]))})
 cases.append(dict(items=items,maxVisible=rng.choice([0,1,3,5]),steps=steps,bindings={'tui.select.down':'j','tui.select.up':'k'} if n%2 else {}))
# Centered scrolling changes the row's item between press and click. Remember the pressed item.
cases.append(dict(items=items,maxVisible=3,steps=[{'op':'mouse','event':{'type':'press','button':'left','y':2}},{'op':'mouse','event':{'type':'click','button':'left','y':2}},{'op':'render','width':80}]))
# Filter changes retain the pending pressed index in upstream, even when now outside the list.
cases.append(dict(items=items,maxVisible=5,steps=[{'op':'mouse','event':{'type':'press','button':'left','y':4}},{'op':'filter','filter':'A'},{'op':'mouse','event':{'type':'click','button':'left','y':0}},{'op':'mouse','event':{'type':'wheel','button':'none','wheelDelta':-1}},{'op':'input','data':E+'[B'},{'op':'render','width':80}]))
# Empty state still cancels; navigation never fabricates an item.
cases.append(dict(items=[],width=1,steps=[{'op':'input','data':E+'[A'},{'op':'input','data':E+'[B'},{'op':'input','data':'\r'},{'op':'input','data':E},{'op':'render','width':1}]))
# Exact lowercase, rather than simple folding: final sigma, dotted I, long s and sharp s.
unicode_items=[dict(value=x,label=x) for x in ['ΟΣ','ΟΣΑ','Σ','ς','İz','IZ','ſoft','Soft','ßeta','ẞeta','𐐀word']]
for query in ['οσ','ος','σ','ς','i','i\u0307','s','ſ','ß','ss','𐐨']:
 cases.append(dict(items=unicode_items,width=80,steps=[{'op':'filter','filter':query},{'op':'render','width':80}]))
# Remapped actions may share a key; up wins before down/confirm/cancel.
for events in ['', 'none']:
 cases.append(dict(items=items,events=events,bindings={action:'j' for action in ['tui.select.up','tui.select.down','tui.select.confirm','tui.select.cancel']},steps=[{'op':'input','data':'j'},{'op':'input','data':'j'},{'op':'render','width':80}]))
 cases.append(dict(items=items,events=events,kitty=True,steps=[{'op':'input','data':key} for key in [E+'[B',E+'[A','\r',E,'\x03']]))
 cases.append(dict(items=items,events=events,steps=[{'op':'mouse','event':{'type':'press','button':'left','y':1}},{'op':'mouse','event':{'type':'click','button':'left','y':1}}]))
expected=batches(oracle,cases)
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 actual=batches(command,[o['input'] for o in original])
 for o,v in zip(original,actual): assert v==o['expected'],(backend,o['name'],o['expected'],v)
 actual=batches(command,cases)
 for i,(c,w,v) in enumerate(zip(cases,expected,actual)):
  assert w==v,(backend,i,c,w,v)
 print(f'{backend}: {len(original)} original SelectList tests and {len(cases)} rendering/filter/keyboard/mouse/callback sequences passed',flush=True)
