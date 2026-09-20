"""Strict connection-order parsing and family selection; inet_pton supplies address reference values."""
import hashlib
import ipaddress
import json
from pathlib import Path
import random
import re
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=ROOT/'build/bend-profiles/dns-transport-teles/bend2'
for suffix in ['c','js']:
    with (ROOT/f'build/connection-order-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/connection-order-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/connection-order.bend','-o',f'build/connection-order.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/connection-order.c','-lpthread','-lm','-o','build/connection-order'],cwd=ROOT,check=True)
def scalars(text):return ','.join(str(ord(x)) for x in text)
def words(value):
    ip=ipaddress.ip_address(value);raw=ip.packed
    return (4,int(ip)) if ip.version==4 else (6,*[int.from_bytes(raw[i:i+4],'big') for i in range(0,16,4)],0)
def text(value):
    return str(ipaddress.IPv4Address(value[1])) if value[0]==4 else str(ipaddress.IPv6Address(b''.join(x.to_bytes(4,'big') for x in value[1:5])))
def encoded(values):return ';'.join(','.join(map(str,value)) for value in values)
base=[words(s) for s in ['127.0.0.1','127.0.0.2','192.0.2.1','::1','::2','::ffff:127.0.0.1','2001:db8::1']]
sequences=[[],*[ [v] for v in base],base,base[::-1],base*3,[base[0]]*8,[base[3]]*8]
rng=random.Random(81828)
for _ in range(128):sequences.append([rng.choice(base) for _ in range(rng.randrange(1,25))])
cases=[(pref,mode,seq) for seq in sequences for pref in [4,6] for mode in ['ordered','paired']]
reference_input=[]
for pref,mode,seq in cases:
    values=seq if mode=='ordered' else [v for family in [pref,10-pref] for v in seq if v[0]==family]
    reference_input.append([dict(address=text(v),family=v[0]) for v in values])
run=subprocess.run(['node','tests/connection_order_reference.mjs'],cwd=ROOT,input=json.dumps(reference_input),capture_output=True,text=True,timeout=60)
assert run.returncode==0 and not run.stderr,run
reference=json.loads(run.stdout)
expected=[encoded([words(row['address']) for row in rows])+(';' if rows else '') for rows in reference['results']]
# Scope is part of native identity. This is a separate value-level assertion;
# it does not pretend the unscoped Node corpus validates interface scopes.
scoped=[(6,0,0,0,1,1),(6,0,0,0,1,2),(6,0,0,0,1,1),base[0]]
for pref in [4,6]:
    cases.append((pref,'ordered',scoped));expected.append(encoded([scoped[0],base[0],scoped[1]])+';')
checks=[]
for backend,cmd in [('native 1',['build/connection-order','--threads','1']),('native 4',['build/connection-order','--threads','4']),('Bun',[str(bun),'build/connection-order.js'])]:
    for start in range(0,len(cases),24):
        args=[arg for pref,mode,values in cases[start:start+24] for arg in [str(pref),mode,encoded(values)]]
        run=subprocess.run([*cmd,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(backend,run)
        assert run.stdout.splitlines()==expected[start:start+24],(backend,start,run.stdout,expected[start:start+24])
    checks.append(dict(backend=backend,cases=len(cases)));print(f'{backend}: {len(cases)} connection-order cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/connection-order.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/connection_order_check.py','tests/connection_order_reference.mjs']
record=dict(scope=__doc__,checks=checks,seed=81828,reference={k:v for k,v in reference.items() if k!='results'},reference_cases=len(reference['results']),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/connection-order-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/connection-order-result.json').write_text(json.dumps(record,indent=2)+'\n')
