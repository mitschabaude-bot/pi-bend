"""Strict numeric-host parsing and family selection; inet_pton supplies address reference values."""
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
    with (ROOT/f'build/numeric-host-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/numeric-host-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/numeric-host.bend','-o',f'build/numeric-host.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/numeric-host.c','-lpthread','-lm','-o','build/numeric-host'],cwd=ROOT,check=True)
def scalars(text):return ','.join(str(ord(x)) for x in text)
def oracle(family,text):
    host,sep,zone=text.partition('%')
    for kind,af,size in [(4,socket.AF_INET,4),(6,socket.AF_INET6,16)]:
        try:raw=socket.inet_pton(af,host)
        except (OSError,ValueError):continue
        if sep and (kind==4 or not zone):break
        if family and family!=kind:return 'family'
        value=str(kind)+':'+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,size,4))
        return value if kind==4 else value+(':'+('zone:'+scalars(zone) if sep else 'none'))
    return 'invalid:'+scalars(text)
texts=['','a','127.0.0.1','255.255.255.255','0.0.0.0','127.1','2130706433','0177.0.0.1','0x7f000001','0x7f.0.0.1','127.0.0.01','1.2.3.256','1.2.3.4.','1.2.3.4:80','[::1]','::','::1','::ffff:192.0.2.1','::ffff:192.000.2.1','2001:db8::1','1::2::3','::1%','fe80::1%lo','fe80::1%0','fe80::1%4294967296','::1%name%tail','::1%é','127.0.0.1%lo',' 127.0.0.1','::1 ','::1\x00','\x00127.0.0.1']
rng=random.Random(112358)
for _ in range(256):
    v4=str(ipaddress.IPv4Address(rng.getrandbits(32)));v6=ipaddress.IPv6Address(rng.getrandbits(128))
    texts += [v4,str(v6),v6.exploded.upper(),str(v6)+'%'+rng.choice(['1','lo','interface','0','4294967295'])]
cases=[(family,text) for family in [0,4,6] for text in texts]
expected=[oracle(*case) for case in cases];checks=[]
for backend,cmd in [('native 1',['build/numeric-host','--threads','1']),('native 4',['build/numeric-host','--threads','4']),('Bun',[str(bun),'build/numeric-host.js'])]:
    for start in range(0,len(cases),32):
        batch=cases[start:start+32];args=[arg for family,text in batch for arg in [str(family),scalars(text)]]
        run=subprocess.run([*cmd,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(backend,run)
        assert run.stdout.splitlines()==expected[start:start+32],(backend,start,run.stdout,expected[start:start+32])
    checks.append(dict(backend=backend,cases=len(cases)));print(f'{backend}: {len(cases)} numeric-host cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/numeric-host.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/numeric_host_check.py']
record=dict(scope=__doc__,checks=checks,seed=112358,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/numeric-host-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/numeric-host-result.json').write_text(json.dumps(record,indent=2)+'\n')
