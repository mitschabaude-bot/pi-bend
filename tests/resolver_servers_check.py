"""Ordered resolver settings-to-server conversion with retained scope diagnostics."""
import ctypes
import hashlib
import ipaddress
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','12','--stats',f'build/resolver-servers-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-servers.bend','-o',f'build/resolver-servers.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-servers.c','-lpthread','-lm','-o','build/resolver-servers'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None,use_errno=True)
aton=libc.__inet_aton_exact;aton.argtypes=[ctypes.c_char_p,ctypes.c_void_p];aton.restype=ctypes.c_int
indexof=libc.if_nametoindex;indexof.argtypes=[ctypes.c_char_p];indexof.restype=ctypes.c_uint

def fields(values):return ''.join(f'{len(x)}:{x}' for x in values)
def parsed(text):
    word=ctypes.create_string_buffer(4)
    if aton(text.encode(),word):return (4,int.from_bytes(word.raw,'big'),None)
    host,sep,zone=text.partition('%')
    try:value=ipaddress.IPv6Address(host)
    except ValueError:return None
    return (6,value,zone if sep else None)

def show(value):
    family,address,zone=value
    if family==4:return '4:'+str(address)
    parts=[int.from_bytes(address.packed[i:i+4],'big') for i in range(0,16,4)]
    return '6:'+','.join(map(str,parts))+':'+('none' if zone is None else 'some:'+zone)

def model(tokens,real=False):
    values=[];invalid=[]
    for token in tokens:
        value=parsed(token)
        if value is None:invalid.append(token)
        else:values.append(value)
    if not values:values=[parsed('127.0.0.1')]
    trace=[];servers=[];issues=[]
    for position,(family,address,zone) in enumerate(values):
        if family==4:
            servers.append(f'server:4:{address}:53');continue
        scope=0;failure=None
        if zone is not None:
            permitted=address in ipaddress.IPv6Network('fe80::/10') or (address.packed[0]==255 and address.packed[1]&15 in (1,2))
            index=0
            if permitted:
                if real:
                    ctypes.set_errno(0);index=indexof(zone.encode());failure=str(ctypes.get_errno() or 5) if not index else None
                else:
                    trace.append('lookup:'+zone)
                    index=7 if zone=='known' else 0
                    failure='19' if not index else None
            numeric=bool(zone) and zone.isascii() and zone.isdecimal() and int(zone)<=2**32-1
            if index:scope=index
            elif numeric:scope=int(zone)
            else:issues.append(f'issue:{position}:{zone}:{failure or "none"}')
        parts=[int.from_bytes(address.packed[i:i+4],'big') for i in range(0,16,4)]
        servers.append('server:6:'+':'.join(map(str,parts))+f':{scope}:53')
    retained=[show(v) for v in values]+['search:'+fields(['file.test','.']), 'options:'+fields(['ndots:2','rotate','weird:7']), 'sort:'+fields(['10.0.0.0/8']), 'invalid:'+fields(invalid), 'unknown:'+fields(['mystery keep'])]
    return trace+retained+servers+issues

def source(tokens):
    return ''.join('nameserver '+token+'\n' for token in tokens)+'search file.test .\noptions ndots:2 rotate weird:7\nsortlist 10.0.0.0/8\nmystery keep'

pool=['127.1','::1','fe80::1%known','fe80::2%missing','2001:db8::1%known','ff02::1%0','::1%4294967295','bad']
sequences=[[],*[[v] for v in pool],*itertools.product(pool,repeat=3)]
sequences.extend([['fe80::1%','bad','fe80::1%4294967296','fe80::1%known'],pool*8,pool*128])
cases=[(['mock',source(tokens)],model(tokens)) for tokens in sequences]
cases.append((['empty','ignored'],[]))
for tokens in [['fe80::1%lo','127.1','ff01::1%lo','fe80::1%missing-if-xyz','::1%lo'],['bad'],['fe80::1%lo']*8]:
    cases.append((['system',source(tokens)],model(tokens,True)))
checks=[]
for backend,command in [('native 1',['build/resolver-servers','--threads','1']),('native 4',['build/resolver-servers','--threads','4']),('Bun',[str(bun),'build/resolver-servers.js'])]:
    for index,(args,want) in enumerate(cases):
        run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,run.stdout[:1000],run.stderr,want[:12])
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} ordered settings/server cases PASS',flush=True)
paths=['packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-resolver.bend','tests/resolver-servers.bend','tests/resolver_servers_check.py']
result=dict(scope=__doc__,checks=checks,maximum_source_server_entries=1024,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-servers-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-servers-result.json').write_text(json.dumps(result,indent=2)+'\n')
