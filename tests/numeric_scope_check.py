"""Strict numeric-scope parsing and family selection; inet_pton supplies address reference values."""
import hashlib
import ipaddress
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=TOOLCHAIN
for suffix in ['c','js']:
    with (ROOT/f'build/numeric-scope-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/numeric-scope-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/numeric-scope.bend','-o',f'build/numeric-scope.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/numeric-scope.c','-lpthread','-lm','-o','build/numeric-scope'],cwd=ROOT,check=True)
def scalars(text):return ','.join(str(ord(x)) for x in text)
def permits(raw):
    n=int.from_bytes(raw[:4],'big')
    return n>>22==1018 or (raw[0]==255 and raw[1]&15 in [1,2])
def model(family,text,mode,name,index):
    host,sep,zone=text.partition('%');value=None
    for kind,af,size in [(4,socket.AF_INET,4),(6,socket.AF_INET6,16)]:
        try:raw=socket.inet_pton(af,host)
        except (ValueError,OSError):continue
        if sep and (kind==4 or not zone):break
        if family and family!=kind:return ['family']
        value=str(kind)+':'+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,size,4));break
    if value is None:return ['invalid:'+scalars(text)]
    if kind==4:return [value]
    if not sep:return [value+':0']
    called=permits(raw);trace=[];failure='none';found=0
    if called:
        if mode=='native':
            try:found=socket.if_nametoindex(zone)
            except (OSError,ValueError):failure='native'
        else:
            trace=['lookup:'+scalars(zone)]
            if zone==name:found=index
            else:failure='missing'
    if not found and zone.isascii() and zone.isdecimal() and int(zone)<=2**32-1:found=int(zone);failure=None
    if found or failure is None:return trace+[value+':'+str(found)]
    return trace+['scope:'+scalars(zone)+':'+failure]
addresses=['::','::1','2001:db8::1','fe7f:ffff::1','fe80::1','febf:ffff::1','fec0::1','ff01::1','ff02::1','ff11::1','ff12::1','ff05::1','ffff::1']
zones=['','0','00','3','0003','4294967295','4294967296','-1','+1',' 1','1 ','1x','0x1','lo','missing-interface','域','١','name%tail']
cases=[]
for address in addresses:
    for zone in zones:
        for family in [0,4,6]:
            for name,index in [('lo',7),('3',77),('lo',0)]:cases.append((family,address+'%'+zone,'injected',name,index))
        cases.append((0,address+'%'+zone,'native','',0))
for text in ['127.0.0.1','::1','fe80::1','127.1','[::1]','bad','127.0.0.1%lo','::1%']:
    for family in [0,4,6]:
        for mode in ['native','injected']:cases.append((family,text,mode,'lo',7))
checks=[]
for backend,cmd in [('native 1',['build/numeric-scope','--threads','1']),('native 4',['build/numeric-scope','--threads','4']),('Bun',[str(bun),'build/numeric-scope.js'])]:
    for start in range(0,len(cases),24):
        batch=cases[start:start+24];args=[arg for family,text,mode,name,index in batch for arg in [str(family),scalars(text),mode,scalars(name),str(index)]]
        expected=[line for case in batch for line in model(*case)]
        run=subprocess.run([*cmd,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(backend,run)
        assert run.stdout.splitlines()==expected,(backend,start,run.stdout,expected)
    checks.append(dict(backend=backend,cases=len(cases)));print(f'{backend}: {len(cases)} numeric-scope cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/numeric-scope.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/numeric_scope_check.py']
record=dict(scope=__doc__,checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/numeric-scope-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/numeric-scope-result.json').write_text(json.dumps(record,indent=2)+'\n')
