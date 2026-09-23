"""Original Input tests and native editing/rendering/input protocol comparisons."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/input')
p.add_argument('--reference',default='/home/agent/code/pi-mono')
a=p.parse_args(); E='\x1b';rng=random.Random(1707)
oracle=['bun','tests/input_reference.ts',a.reference,'build/input-reference/node_modules']
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-4000:])
 result=json.loads(r.stdout)
 assert len(result)==len(values),(command,'result count',len(values),len(result))
 return result
def batches(command,values):
 out=[]
 for i in range(0,len(values),8):out.extend(run(command,values[i:i+8]))
 return out
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
cases=[]
keys=['a','b',' ','word',E+'[D',E+'[C','\x01','\x05','\x7f',E+'[3~','\x17',E+'d','\x15','\x0b','\x19',E+'y',E+'b',E+'f',E+'[45;5u','\r','\n',E,'\x03',E+'[97u',E+'[98;2u','\x00','\x85',E+'[A','']
for i in range(120):
 steps=[dict(op='set',value=rng.choice(['hello world','foo.bar baz','one two three','prefix|suffix','']))]
 for j in range(32):
  op=rng.randrange(6)
  if op<=3:steps.append(dict(op='input',data=rng.choice(keys)))
  elif op==4:steps.append(dict(op='render',width=rng.choice([0,1,2,3,4,8,15,40]),focused=rng.choice([True,False])))
  else:steps.append(dict(op='mouse',event=dict(type=rng.choice(['press','move','click']),button=rng.choice(['left','right']),x=rng.choice([-2,0,1,2,3,8,50]),y=rng.choice([-1,0,1]))))
 cases.append(dict(options=rng.choice([{},dict(prompt='',placeholder='Find transcript',style='dim'),dict(prompt='>>> ')]),steps=steps,kitty=i%2==0,bindings={'tui.editor.cursorLeft':'ctrl+j','tui.editor.deleteToLineEnd':'alt+k'} if i%3==0 else {}))
for text in ['界界abc界','e\u0301 👩\u200d💻 🇦🇧','ＡＢＣＤＥＦＧ','hello world','\x1b[31mred\x1b[39m']:
 for width in [0,1,2,3,4,5,8,12,20]:
  steps=[dict(op='set',value=text)]
  for key in [E+'[C',E+'[C',E+'[C','\x05','\x01',E+'[C','\x7f',E+'[3~',E+'[45;5u']:
   steps.extend([dict(op='input',data=key),dict(op='render',width=width,focused=True)])
  cases.append(dict(steps=steps))
for payload in ['a\r\nb\nc\rd\te','界👩\u200d💻','x\x00\x85y','', 'tail'+E+'[200~nested'+E+'[201~']:
 encoded=E+'[200~'+payload+E+'[201~'
 for split in range(len(encoded)+1):
  cases.append(dict(steps=[dict(op='input',data='left '),dict(op='input',data=encoded[:split]),dict(op='input',data=encoded[split:]),dict(op='input',data=E+'[45;5u'),dict(op='render',width=20)]))
# Multiple completed pastes and a trailing ordinary key in one input event.
cases.append(dict(steps=[dict(op='input',data=E+'[200~first'+E+'[201~'+E+'[200~second'+E+'[201~!'),dict(op='render',width=30)]))
# Rendering a placeholder or an undersized prompt retains the prior mouse-scroll origin.
cases.append(dict(options=dict(placeholder='hint',style='dim'),steps=[dict(op='input',data='abcdefghijklmnopqrstuvwxyz'),dict(op='render',width=8),dict(op='set',value=''),dict(op='render',width=8),dict(op='set',value='abcdef'),dict(op='render',width=1),dict(op='mouse',event=dict(type='press',button='left',x=2,y=0)),dict(op='render',width=12)]))
cases.append(dict(steps=[dict(op='input',data=E+'[200~'+'x'*30000+E+'[201~'),dict(op='render',width=20),dict(op='input',data=E+'[45;5u')]))
cases.append(dict(steps=[dict(op='set',value='e'+'\u0301'*10000),dict(op='input',data=E+'[C'),dict(op='render',width=8),dict(op='input',data='\x7f'),dict(op='input',data=E+'[45;5u')]))
prepared=batches(oracle,cases)
# Existing approved terminal-scanner corrections are independent expectations.
# Editing CSI bytes leaves literal "["/"[3" fragments; native width retains
# them. A complete bracketed-paste CSI inside pasted data is zero-width.
corrected=0
for case in prepared:
 for step,obs in zip(case['input']['steps'],case['expected']['observations']):
  if step['op']!='render':continue
  expected_line=None
  if obs['value']==E+'[31mred'+E+'[39m' and step['width']>=6 and obs['cursor'] in [2,3]:
   if obs['cursor']==2:expected_line='> '+E+'['+E+'_pi:c\x07'+E+'[7m3'+E+'[27m1mred'+E+'[39m'
   else:expected_line='> '+E+'[3'+E+'_pi:c\x07'+E+'[7m1'+E+'[27mmred'+E+'[39m'
   expected_line+=' '*max(0,step['width']-9)
  if obs['value']=='left tail'+E+'[200~nested' and step['width']==20:
   expected_line='> '+obs['value']+E+'[7m '+E+'[27m  '
  if expected_line is not None and obs['lines']!=[expected_line]:
   corrected+=1;obs['lines']=[expected_line]
missing=dict(input=dict(steps=[dict(op='set',value='ไทย'),dict(op='input',data='\x05'),dict(op='input',data='\x17',segments='Thai')]),expected=dict(observations=[dict(value='ไทย',cursor=0),dict(value='ไทย',cursor=3),dict(value='ไทย',cursor=3,error=dict(missingWordEngine='Thai'))],calls=[]))
all_cases=original+prepared+[missing]
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 actual=batches(command,[case['input'] for case in all_cases])
 for index,(case,value) in enumerate(zip(all_cases,actual)):
  assert value==case['expected'],(backend,index,case.get('name'),case['input'],case['expected'],value)
 print(f'{backend}: {len(set(c["name"] for c in original))} original Input tests ({len(original)} traces), {len(prepared)} editing/render/mouse/paste sequences, {corrected} approved scanner observations and a missing-engine check passed with explicit lexical fixtures',flush=True)
