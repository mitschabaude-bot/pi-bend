"""Structured parallel pairs and candidate-paired DNS search with deterministic IO barriers."""
from channel_audit import instrument
import hashlib
import itertools
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2'
audit='''\nstatic void __attribute__((destructor)) pair_audit(void) {
 unsigned live=0;
 for(u32 i=0;i<chan_len;i++)live+=chan_rows[i].live;
 fprintf(stderr,"AUDIT %u %u\\n",live,io_park.head!=NULL);
}\n'''
for stem in ['io-pair','dns-search-parallel']:
 for suffix in ['c','js']:
  with (ROOT/f'build/{stem}-{suffix}.log').open('w') as log:
   subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{stem}-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),f'tests/{stem}.bend','-o',f'build/{stem}.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
 (ROOT/f'build/{stem}-audit.c').write_text((ROOT/f'build/{stem}.c').read_text()+audit)
 subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{stem}-audit.c','-lpthread','-lm','-o',f'build/{stem}'],cwd=ROOT,check=True)
 (ROOT/f'build/{stem}-audit.js').write_text(instrument((ROOT/f'build/{stem}.js').read_text()))

def wire(name):
 raw=b''.join(bytes([len(part)])+part.encode() for part in name.split('.'))+b'\0'
 return ''.join(str(byte)+',' for byte in raw)

def search_expected(case):
 first,left,right=case;left=left.split(',');right=right.split(',');trace='';result='error:1';calls=0
 for origin,name in [('suffix:0','a.x'),('suffix:1','a.y'),('final','a')]:
  a=left[calls] if calls<len(left) else 'n';b=right[calls] if calls<len(right) else 'n';calls+=1
  for side in ('LR' if first=='L' else 'RL'):trace+=side+':'+origin+':'+wire(name)+';'
  if a.startswith('h'):result='halt:left:'+a[1:];break
  if b.startswith('h'):result='halt:right:'+b[1:];break
  if 'a' in [a,b]:result='ok:'+'+'.join(['exact answer payload']*((a=='a')+(b=='a')));break
 return [result,trace,f'calls:{calls}',f'calls:{calls}']

pairs=list(itertools.product(['L','R'],['ok','fail'],['ok','fail']))*32
scripts=[','.join(tokens) for tokens in itertools.product(['n','a','hfailure'],repeat=3)]
searches=list(itertools.product(['L','R'],scripts,scripts))
checks=[]
for backend in ['native 1','native 4','Bun']:
 for stem,cases in [('io-pair',pairs),('dns-search-parallel',searches)]:
  command=[str(bun),f'build/{stem}-audit.js'] if backend=='Bun' else [f'build/{stem}','--threads',backend[-1]]
  for start in range(0,len(cases),32):
   batch=cases[start:start+32]
   expected=[]
   for case in batch:
    if stem=='io-pair':
     first,left,right=case
     expected += [('error:41' if left=='fail' else 'value:L')+'/'+('error:73' if right=='fail' else 'value:R'),'LR' if first=='L' else 'RL']
    else:expected+=search_expected(case)
   run=subprocess.run([*command,*[arg for case in batch for arg in case]],cwd=ROOT,capture_output=True,text=True,timeout=15)
   assert run.returncode==0,(backend,stem,start,run.stderr,run.stdout)
   assert run.stdout.splitlines()==expected,(backend,stem,start,run.stdout,expected)
   assert run.stderr==('AUDIT 0 0 0\n' if backend=='Bun' else 'AUDIT 0 0\n'),(backend,stem,start,run.stderr)
  checks.append(dict(backend=backend,fixture=stem,cases=len(cases)))
  print(f'{backend}: {len(cases)} {stem} cases PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
for stem in ['io-pair','dns-search-parallel']:imports(ROOT/f'tests/{stem}.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/io_pair_check.py','tests/channel_audit.py']
record=dict(scope=__doc__,checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={f'{stem}-{s}':json.loads((ROOT/f'build/{stem}-{s}-build.json').read_text()) for stem in ['io-pair','dns-search-parallel'] for s in ['c','js']})
(ROOT/'build/io-pair-result.json').write_text(json.dumps(record,indent=2)+'\n')
