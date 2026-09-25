"""Pinned overlay assertions and exact ANSI/Unicode composition comparisons."""
from upstream_pin import UPSTREAM
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--prefix',type=Path,default=ROOT/'build/tui-composite');p.add_argument('--width-reference',default='/home/agent/code/pi-bend-tui-ansi/build/ansi-reference/node_modules/get-east-asian-width/index.js');p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
oracle=['bun','tests/tui_composite_reference.ts',str(UPSTREAM),a.width_reference]
def run(command,values):
 result=subprocess.run(command+[json.dumps(values,ensure_ascii=False)],cwd=ROOT,text=True,capture_output=True,timeout=60)
 assert result.returncode==0,(result.returncode,result.stderr[-2000:])
 return json.loads(result.stdout)
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
cases=[v['input'] for v in original['calls']];expected=[v['result'] for v in original['calls']]
rng=random.Random(2709);E='\x1b';texts=['','abc','abcd让EFGH','界x界','🇦🇧🇨abc','👩\u200d💻 abc','a\u0301b',E+'[31mred'+E+'[0m',E+']8;;https://example.com\x07link'+E+']8;;\x07','a\tb']
extra=[]
for _ in range(600):
 total=rng.randrange(25);start=rng.randrange(total+1);width=rng.randrange(total-start+1)
 extra.append(dict(base=rng.choice(texts),overlay=rng.choice(texts),start=start,width=width,total=total))
for prefix in [E+'_G',E+']1337;File=']:
 for lead in ['',E+'[2A','ordinary text']:
  extra.append(dict(base=lead+prefix+'payload\x1b\\',overlay='overlay',start=2,width=4,total=12))
# Bounds that extend beyond the viewport still clip the complete composed line.
extra.extend(dict(base='abc界',overlay='界abc',start=start,width=width,total=4) for start,width in [(9,2),(0,9),(3,9)])
for i in range(0,len(extra),40):
 chunk=extra[i:i+40];cases.extend(chunk);expected.extend(run(oracle,chunk))
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 for i in range(0,len(cases),40):
  actual=run(command,cases[i:i+40]);assert actual==expected[i:i+40],(backend,cases[i:i+40],actual,expected[i:i+40])
 print(f'{backend}: two original compositor results and {len(extra)} exact overlay/image/boundary comparisons passed',flush=True)
