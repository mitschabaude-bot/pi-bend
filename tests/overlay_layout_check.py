"""Pure overlay geometry comparisons against the hash-pinned source resolver."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--prefix',type=Path,default=ROOT/'build/overlay-layout');p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
def run(command,values):
 r=subprocess.run(command+[json.dumps(values)],cwd=ROOT,text=True,capture_output=True,timeout=60)
 assert r.returncode==0,(r.returncode,r.stderr[-2000:]);return json.loads(r.stdout)
anchors=['center','top-left','top-right','bottom-left','bottom-right','top-center','bottom-center','left-center','right-center']
cases=[]
for anchor in anchors:
 for columns,rows,height in [(80,24,5),(0,0,0),(1,1,30),(10,5,40),(200,100,0)]:
  for margin in [0,2,100,{'top':2,'right':3,'bottom':5,'left':7}]:
   cases.append(dict(columns=columns,rows=rows,height=height,options=dict(anchor=anchor,margin=margin)))
rng=random.Random(28631)
for _ in range(1000):
 opts={'anchor':rng.choice(anchors),'offsetX':rng.randrange(-200,201),'offsetY':rng.randrange(-200,201)}
 for key in ['width','row','col','maxHeight']:
  if rng.randrange(3):opts[key]=rng.choice([0,1,100,400,'0%','50%','100%','150%','33.333%','0.125%',('9'*308+'%')])
 opts['margin']={key:rng.randrange(0,100) for key in ['top','right','bottom','left']};opts['minWidth']=rng.randrange(0,300)
 cases.append(dict(columns=rng.randrange(0,300),rows=rng.randrange(0,120),height=rng.randrange(0,400),options=opts))
expected=[]
for i in range(0,len(cases),40):expected.extend(run(['bun','tests/overlay_layout_reference.ts'],cases[i:i+40]))
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 for i in range(0,len(cases),40):
  got=run(command,cases[i:i+40]);want=expected[i:i+40]
  for value,left,right in zip(cases[i:i+40],got,want):assert left==right,(backend,value,left,right)
 bad=[dict(columns=80,rows=24,height=5,options={key:percent}) for key in ['width','row','col','maxHeight'] for percent in ['-1%','NaN%','Infinity%']]
 assert run(command,bad)==['invalid-percentage']*len(bad)
 print(f'{backend}: {len(cases)} source geometry comparisons and {len(bad)} invalid percentages passed',flush=True)
