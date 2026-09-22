"""Native report classification and paired decisions for both explicitly selected precedence orders."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);candidate=p.parse_args().candidate.resolve()
bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
 with (ROOT/f'build/dns-pair-result-{suffix}.log').open('w') as log:
  subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-pair-result-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-pair-result.bend','-o',f'build/dns-pair-result.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-pair-result.c','-lpthread','-lm','-o','build/dns-pair-result'],cwd=ROOT,check=True)
# These are full typed report fixtures, not a simulation of network receipt
# order or a libc end-to-end resolver oracle. Errno constants are Linux values.
classification={
 'a4':'answer','a6':'answer','empty':'reply:0',
 'u2':'unavailable:server','u4':'unavailable:temporary','u5':'unavailable:temporary',
 'uempty':'unavailable:temporary','uexpired2':'unavailable:server',
 'uparent':'terminal','udefault':'terminal','utimeout':'unavailable:temporary',
 'uerrno111':'unavailable:refused','uerrno110':'unavailable:temporary',
 'teof':'unavailable:temporary','terrno111':'unavailable:refused','terrno110':'unavailable:temporary',
 'tcleanup':'terminal','abort':'terminal','entropy':'terminal','invalid':'terminal',
 'unsupported':'terminal','noservers':'terminal','readsize':'terminal',
}
for code in [1,2,3,4,5,6,16,23,4095]:classification['c'+str(code)]='reply:'+str(code)
def response(code):return {0:'empty',2:'server',3:'missing'}.get(code,'unrecoverable')
def expected(case):
 order,left,right=case;a=classification[left];b=classification[right];pair=a+'/'+b
 if 'terminal' in [a,b]:result='halt:'+pair
 elif 'answer' in [a,b]:result='answer:'+pair
 else:
  ordered=[a,b] if order=='4' else [b,a]
  codes=[int(value.split(':')[1]) for value in ordered if value.startswith('reply:')]
  if codes:
   failure=response(next((code for code in codes if code),0))
  else:failure=ordered[0].split(':')[1]
  result='failed:'+failure
 return pair+'='+result
cases=list(itertools.product(['4','6'],classification,classification));wanted=[expected(case) for case in cases];checks=[]
for backend,cmd in [('native 1',['build/dns-pair-result','--threads','1']),('native 4',['build/dns-pair-result','--threads','4']),('Bun',[str(bun),'build/dns-pair-result.js'])]:
 for start in range(0,len(cases),64):
  batch=cases[start:start+64]
  run=subprocess.run([*cmd,*[arg for case in batch for arg in case]],cwd=ROOT,capture_output=True,text=True,timeout=30)
  assert run.returncode==0 and not run.stderr,(backend,start,run)
  assert run.stdout.splitlines()==wanted[start:start+64],(backend,start,run.stdout,wanted[start:start+64])
 checks.append(dict(backend=backend,cases=len(cases)))
 print(f'{backend}: {len(cases)} classified pairs PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-pair-result.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_pair_result_check.py']
record=dict(scope=__doc__,checks=checks,candidate=str(candidate),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-pair-result-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-pair-result-result.json').write_text(json.dumps(record,indent=2)+'\n')
