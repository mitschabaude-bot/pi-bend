"""Actual TuiBase overlay composition and displayed-frame mouse dispatch."""
from upstream_pin import UPSTREAM
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',type=Path,default=ROOT/'build/tui-base');a=p.parse_args()
oracle=['bun','tests/tui_base_reference.ts',str(UPSTREAM),str(ROOT/'build/input-reference/node_modules/get-east-asian-width/index.js')]
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False)],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-3000:])
 return json.loads(r.stdout)
E='\x1b';rng=random.Random(835)
# Keep construction explicit so overrides do not silently collide with defaults.
def item(id,**kw):return dict(dict(id=id,order=id,lines=['overlay'],mouse='handled',options={}),**kw)
def case(overlays,**kw):return dict(dict(base=['base'],width=12,height=5,overlays=overlays,events=[dict(x=x,y=y) for x,y in [(-1,0),(0,-1),(0,0),(3,2),(11,4),(12,4),(4,5)]],removeLive=False),**kw)
cases=[case([]),case([],base=[]),case([item(1,hidden=True)]),case([item(1,visible=False)]),case([item(1,lines=[])]),case([item(1,lines=['one','two','three'],options=dict(width=4,maxHeight=1,row=0,col=0))])]
for mode in ['none','unhandled','handled','capture','focus','nested','nested-no-focus']:
 cases.append(case([item(1,order=2,mouse='handled',options=dict(width=5,row=0,col=0)),item(2,order=3,mouse=mode,options=dict(width=3,row=0,col=1))],events=[dict(x=x,y=y) for x,y in [(0,0),(1,0),(2,0),(3,0),(4,0),(1,1)]],removeLive=True))
for lengths in [0,1,5,12]:
 for anchor in ['top-left','center','bottom-right']:
  cases.append(case([item(1,lines=['界abcdefgh','second','third'],options=dict(width=3,anchor=anchor))],base=['line'+str(i) for i in range(lengths)]))
# Stable equal-order overlays render and hit in original insertion order.
cases.append(case([item(3,order=1),item(2,order=1),item(1,order=1)],events=[dict(x=1,y=2)]))
for image in [E+'_Gpayload'+E+'\\',E+']1337;File=payload\x07']:
 cases.append(case([item(1,lines=['overlay'],options=dict(width=4,row=0,col=0))],base=[image]))
 cases.append(case([item(1,lines=[image],options=dict(width=4,row=0,col=0))],base=['under image']))
texts=['','text','界abc界','e\u0301👩\u200d💻','🇦🇧🇨',E+'[31mred'+E+'[0m','a\tb',E+']8;;https://example.test\x07link'+E+']8;;\x07']
for _ in range(100):
 width=rng.randrange(3,30);height=rng.randrange(2,10)
 entries=[]
 for i in range(rng.randrange(0,5)):
  options=dict(width=rng.choice([rng.randrange(1,width+1),'50%','100%']),anchor=rng.choice(['top-left','center','bottom-right','top-center','right-center']))
  if rng.randrange(3)==0:options['maxHeight']=rng.choice([1,2,'50%'])
  if rng.randrange(4)==0:options.update(row='25%',col='75%')
  entries.append(item(i+1,order=rng.randrange(4),lines=[rng.choice(texts) for _ in range(rng.randrange(5))],options=options,mouse=rng.choice(['none','unhandled','handled','capture','focus','nested','nested-no-focus']),hidden=rng.randrange(6)==0,visible=rng.randrange(6)!=0))
 cases.append(case(entries,width=width,height=height,base=[rng.choice(texts) for _ in range(rng.randrange(14))],events=[dict(x=rng.randrange(-1,width+1),y=rng.randrange(-1,height+1)) for _ in range(8)],removeLive=rng.randrange(2)==0))
expected=[]
for start in range(0,len(cases),8):expected.extend(run(oracle,cases[start:start+8]))
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 for start in range(0,len(cases),8):
  actual=run(command,cases[start:start+8]);assert len(actual)==len(expected[start:start+8])
  for offset,(got,want) in enumerate(zip(actual,expected[start:start+8])):
   if got!=want:
    Path('/tmp/tui-base-failure.json').write_text(json.dumps(dict(index=start+offset,case=cases[start+offset],actual=got,expected=want),ensure_ascii=False,indent=2))
    raise AssertionError((backend,start+offset,'/tmp/tui-base-failure.json'))
 print(f'{backend}: {len(cases)} exact composition/mouse cases passed (render order/width, bounds, viewport, retained displayed targets)',flush=True)
