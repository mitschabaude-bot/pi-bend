"""IPv6 scope policy and resolver endpoint conversion, with numeric libc checks."""
import hashlib
import ipaddress
import json
from pathlib import Path
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=ROOT/'build/bend-hostname-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/ipv6-scope-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/ipv6-scope.bend','-o',f'build/ipv6-scope.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/ipv6-scope.c','-lpthread','-lm','-o','build/ipv6-scope'],cwd=ROOT,check=True)

def permits(address):
    value=ipaddress.IPv6Address(address)
    return value in ipaddress.IPv6Network('fe80::/10') or (value.packed[0]==255 and value.packed[1]&15 in (1,2))

def model(address,scope,name,index):
    called=permits(address)
    known=called and scope==name
    numeric=bool(scope) and scope.isascii() and scope.isdecimal()
    number=int(scope) if numeric else None
    if known and index: result=index
    elif numeric and number<=2**32-1: result=number
    else: result=None
    trace=['lookup:'+scope] if called else []
    failure='none' if not called or known else 'missing'
    strict=f'index:{result}' if result is not None else f'invalid:{scope}:{failure}'
    resolved=f'resolved:{result}' if result is not None else 'defaulted:0'
    return trace+[strict]+trace+[resolved],result

addresses=['::','::1','2001:db8::1','fe7f:ffff::1','fe80::1','febf:ffff::1','fec0::1','ff01::1','ff02::1','ff11::1','ff12::1','ff05::1','ffff::1']
scopes=['','0','00','3','0003','4294967295','4294967296','18446744073709551616','-1','+1',' 1','1 ','1\t','1x','0x1','eth0','lo','missing-interface','域','١','0'*2048,'0'*2048+'3']
cases=[]
for address in addresses:
    for scope in scopes:
        for name,index in [('eth0',7),('3',77),('eth0',0)]:
            want,_=model(address,scope,name,index)
            cases.append(([address,scope,name,str(index)],want))
# Oracle uses AI_NUMERICHOST: no network requests or search-domain expansion.
loopback=socket.if_nametoindex('lo')
oracle=0
for address in addresses:
    for scope in scopes:
        want,result=model(address,scope,'lo',loopback)
        try:
            rows=socket.getaddrinfo((address+'%'+scope).encode(),53,socket.AF_INET6,socket.SOCK_STREAM,0,socket.AI_NUMERICHOST)
            actual=rows[0][4][3]
        except socket.gaierror:
            actual=None
        assert result==actual,(address,scope,result,actual)
        cases.append(([address,scope,'lo',str(loopback)],want));oracle+=1
for address,want in [('127.0.0.1',['v4']),('127.1',['v4']),('::1',['resolved:0']),('fe80::1',['resolved:0']),('fe80::1%eth0',['lookup:eth0','resolved:7']),('::1%eth0',['defaulted:0']),('fe80::1%',['lookup:','defaulted:0'])]:
    cases.append(([address,'eth0','7'],want))
checks=[]
for backend,command in [('native 1',['build/ipv6-scope','--threads','1']),('native 4',['build/ipv6-scope','--threads','4']),('Bun',[str(bun),'build/ipv6-scope.js'])]:
    for index,(args,want) in enumerate(cases):
        run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,timeout=15)
        assert run.returncode==0 and not run.stderr and run.stdout==('\n'.join(want)+'\n').encode(),(backend,index,args,run,want)
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} IPv6 scope cases PASS',flush=True)
paths=['packages/runtime/src/ipv6-scope.bend','packages/runtime/src/resolver-scope.bend','tests/ipv6-scope.bend','tests/ipv6_scope_check.py']
result=dict(scope=__doc__,checks=checks,libc_numeric_host_cases=oracle,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/ipv6-scope-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/ipv6-scope-result.json').write_text(json.dumps(result,indent=2)+'\n')
