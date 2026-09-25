"""Strict incremental UTF-8 against Python's independent strict codec, including error offsets."""
import codecs
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import subprocess
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=TOOLCHAIN
for suffix in ['c','js']:
 with (ROOT/f'build/utf8-strict-{suffix}.log').open('w') as log:
  subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/utf8-strict-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/utf8-strict.bend','-o',f'build/utf8-strict.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/utf8-strict.c','-lpthread','-lm','-o','build/utf8-strict'],cwd=ROOT,check=True)
def reference(values,mode):
 # Python's incremental codec can defer rejecting ED A0 until a third byte.
 # Finalize each prefix to distinguish an incomplete but extendable prefix
 # from one that is already irreparably malformed, without reimplementing UTF-8.
 prefix=b''
 for offset,value in enumerate(values):
  if value>255:return f'byte:{offset}:{value}'
  prefix+=bytes([value])
  try:prefix.decode('utf-8','strict')
  except UnicodeDecodeError as error:
   if error.reason!='unexpected end of data':return f'invalid:{offset}:{value}'
 try:text=prefix.decode('utf-8','strict')
 except UnicodeDecodeError:return f'incomplete:{len(values)}'
 if mode=='strip' and text.startswith('\ufeff'):text=text[1:]
 return 'ok:'+','.join(str(ord(c)) for c in text)

values=[[],[256],[4294967295],[65,256],[0xef,0xbf,0xbd],[0xef,0xbb,0xbf]*2,[65,0xef,0xbb,0xbf],list(b'abc'),[0xc0,0x80],[0xe0,0x80,0x80],[0xed,0xa0,0x80],[0xf4,0x90,0x80,0x80],[0xf0,0x90,0x80],[0xe2,65,0xff],[0xf5,0x80]]
values += [[i] for i in range(256)]
rng=random.Random(478193)
for _ in range(768):
 point=rng.randrange(0x110000)
 if not 0xd800<=point<=0xdfff:values.append(list(chr(point).encode()))
 values.append([rng.randrange(256) for _ in range(rng.randrange(2,9))])
cases=[]
for valueset in values:
 for mode in ['preserve','strip']:
  wanted=reference(valueset,mode)
  for split in range(len(valueset)+1):
   chunks=[valueset[:split],[],valueset[split:]]
   cases.append((mode,'|'.join(','.join(map(str,c)) for c in chunks),wanted))
rows=[]
for backend,cmd in [('native 1',['build/utf8-strict','--threads','1']),('native 4',['build/utf8-strict','--threads','4']),('Bun',[str(bun),'build/utf8-strict.js'])]:
 for start in range(0,len(cases),128):
  batch=cases[start:start+128];run=subprocess.run([*cmd,*[v for mode,text,_ in batch for v in [mode,text]]],cwd=ROOT,capture_output=True,text=True,timeout=30)
  assert run.returncode==0 and not run.stderr and len(run.stdout.splitlines())==len(batch),(backend,start,run)
  for (mode,text,want),got in zip(batch,run.stdout.splitlines()):assert got==want,(backend,mode,text,got,want)
 rows.append(dict(backend=backend,cases=len(cases)));print(f'{backend}: {len(cases)} strict UTF-8 cases PASS',flush=True)
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/utf8-strict.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/utf8_strict_check.py']
record=dict(scope=__doc__,checks=rows,seed=478193,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/utf8-strict-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/utf8-strict-result.json').write_text(json.dumps(record,indent=2)+'\n')
