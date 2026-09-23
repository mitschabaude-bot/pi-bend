"""Pinned TUI cursor extraction and line-reset frame preparation."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',type=Path,default=ROOT/'build/tui-frame');a=p.parse_args()
oracle=['bun','tests/tui_frame_reference.ts',str(ROOT.parent/'pi-mono'),str(ROOT/'build/input-reference/node_modules/get-east-asian-width/index.js')]
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False)],cwd=ROOT,capture_output=True,text=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-3000:])
 return json.loads(r.stdout)
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
cases=[c['input'] for c in original['calls']];expected=[c['result'] for c in original['calls']]
E='\x1b';M=E+'_pi:c\x07';reset=E+'[0m'+E+']8;;\x07';rng=random.Random(1394)
texts=['','plain','界a界','🇦🇧🇨','👩\u200d💻','e\u0301a','กำabc','ກຳabc','a\tb',E+'[31mred'+E+'[0m',E+']8;;https://example.test/a\tb\x07label\ttext'+E+']8;;\x07',E+']0;window\ttitle'+E+'\\','a'+E+'_payload\tdata'+E+'\\b']
extra=[]
# Lowest visible row wins; only its first marker is removed.
for lines in [[],[''],['absent'],[M],[M+M],['a'+M+'b'+M+'c'],['a'+M,'plain','界'+M+M],[M,'plain'],['above'+M,'middle'+M,'last'+M]]:
 for height in range(0,len(lines)+3):
  for op in ['cursor','frame']:extra.append(dict(op=op,lines=lines,height=height))
for value in texts:
 extra.append(dict(op='reset',lines=[value,value+reset]))
 for marker in [M+'tail',value+M+'tail',value+M+M+'tail']:
  for op in ['cursor','frame']:extra.append(dict(op=op,lines=['hidden'+M,marker,'suffix'],height=2))
for prefix in [E+'_G',E+']1337;File=']:
 for lead in ['',E+'[2A','ordinary text']:
  line=lead+prefix+'payload\tกำ'+E+'\\'
  extra.extend([dict(op='reset',lines=[line]),dict(op='frame',lines=[line+M],height=1),dict(op='cursor',lines=[line+M],height=1)])
for _ in range(220):
 lines=[]
 for row in range(rng.randrange(0,12)):
  line=rng.choice(texts)
  if rng.randrange(3)==0:line+=M+rng.choice(texts)
  if rng.randrange(4)==0:line=M+line+M
  lines.append(line)
 extra.append(dict(op=rng.choice(['reset','cursor','frame']),lines=lines,height=rng.randrange(16)))
extra += [dict(op='frame',lines=['x'*10000+M+'tail'],height=1),dict(op='cursor',lines=['x'*10000],height=1),dict(op='frame',lines=['row']*1000+[M,'last'],height=2)]
for i in range(0,len(extra),30):
 chunk=extra[i:i+30];cases.extend(chunk);expected.extend(run(oracle,chunk))
# Approved complete-CSI grammar: CSI + image control string has zero
# visible columns even when the legacy source scanner leaks payload bytes.
corrections=0
for case,want in zip(cases,expected):
 if case['op'] in ('cursor','frame') and len(case['lines'])==1 and any(case['lines'][0].startswith(E+'[2A'+prefix) for prefix in [E+'_G',E+']1337;File=']):
  assert want['cursor'] is not None
  if want['cursor']['col']!=0:corrections+=1
  want['cursor']['col']=0
assert corrections==4,corrections
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 for start in range(0,len(cases),30):
  actual=run(command,cases[start:start+30]);assert len(actual)==len(expected[start:start+30])
  for offset,(got,want) in enumerate(zip(actual,expected[start:start+30])):
   if got!=want:
    Path('/tmp/tui-frame-failure.json').write_text(json.dumps(dict(index=start+offset,case=cases[start+offset],actual=got,expected=want),ensure_ascii=False,indent=2))
    raise AssertionError((backend,start+offset,'/tmp/tui-frame-failure.json'))
 print(f'{backend}: {len(original["names"])} relevant original normalization tests ({len(original["calls"])} frame traces) and {len(extra)-corrections} exact cursor/reset/image/viewport comparisons and {corrections} approved scanner corrections passed',flush=True)
