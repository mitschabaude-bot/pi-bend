"""Normalize valid scalar strings on all backends; raw surrogate units on native.

Bun rejects constructing surrogate Char values (known BEND-021). Those explicit
constructor cases remain native-only, rather than patching production behavior.
"""
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run([str(bun),str(compiler),'tests/utf16-normalize.bend','-o',f'build/utf16-normalize.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O1','build/utf16-normalize.c','-lpthread','-lm','-o','build/utf16-normalize'],cwd=ROOT,check=True)

def normalize(values):
    result=[];index=0
    while index<len(values):
        c=values[index]
        if 0xd800<=c<=0xdbff and index+1<len(values) and 0xdc00<=values[index+1]<=0xdfff:
            result.append(0x10000+(c-0xd800)*1024+values[index+1]-0xdc00);index+=2
        else:result.append(c);index+=1
    return result

cases=[[],[0xd800],[0xdc00],[0xd800,0xdc00],[0xd800,0xd801,0xdc00],[0xdbff,0xdfff],[0x10ffff],
       [0,0xd800,65,0xdc00,0xd801],list(range(0xd800,0xe000)),[0xd800,0xdc00]*1000]
rng=random.Random(1985);alphabet=[0,65,0xd7ff,0xd800,0xdbff,0xdc00,0xdfff,0xe000,0xffff,0x10000,0x1f600,0x10ffff]
for _ in range(400):cases.append(rng.choices(alphabet,k=rng.randrange(1,100)))
for _ in range(400):cases.append(rng.choices([0,65,0xd7ff,0xe000,0xffff,0x10000,0x1f600,0x10ffff],k=rng.randrange(1,100)))
expected=[','.join(map(str,normalize(case)))+(',' if case else '') for case in cases]
long=normalize([65,0,0x10000,0x1f600,0x10ffff]*20000)
h=2166136261
for c in long:h=((h*16777619)&0xffffffff)^c
head=f'{len(long)}:{h}';rows=[]
for label,command in [('native 1',['build/utf16-normalize','--threads','1']),('native 4',['build/utf16-normalize','--threads','4']),('Bun',[str(bun),'build/utf16-normalize.js'])]:
    selected=[(case,want) for case,want in zip(cases,expected) if label!='Bun' or all(not 0xd800<=c<=0xdfff for c in case)]
    arguments=[','.join(map(str,case)) for case,want in selected]
    run=subprocess.run([*command,*arguments],cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert run.returncode==0 and not run.stderr,(label,run.returncode,run.stderr)
    actual=run.stdout.splitlines();assert actual==[head,*[want for case,want in selected]],(label,actual[:4],head,expected[:3])
    rows.append(dict(backend=label,short_cases=len(selected),raw_surrogate_construction=label!='Bun',long_input_scalars=100000,long_output_scalars=len(long),digest=h));print(label+': UTF-16 normalization PASS',flush=True)
paths=['packages/runtime/src/utf16.bend','tests/utf16-normalize.bend','tests/utf16_normalize_check.py','build/utf16-normalize','build/utf16-normalize.js']
(ROOT/'build/utf16-normalize-result.json').write_text(json.dumps(dict(cases=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}),indent=2)+'\n')
