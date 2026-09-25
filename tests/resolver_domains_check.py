"""Configured search suffixes retain typed failures and libc query/error behavior."""
import ctypes
from concurrent.futures import ThreadPoolExecutor
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import struct
import subprocess
import threading

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-domains-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-domains.bend','-o',f'build/resolver-domains.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-domains.c','-lpthread','-lm','-o','build/resolver-domains'],cwd=ROOT,check=True)
subprocess.run(['cc','-std=c11','-O2','tests/dns-search-oracle.c','-lresolv','-o','build/dns-search-oracle'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def wire(text):
    buf=ctypes.create_string_buffer(256)
    if pton(text.encode(),buf,256)<0:return None
    data=buf.raw;at=0
    while data[at]:at+=data[at]+1
    return data[:at+1]
def csv(data):return 'invalid' if data is None else ''.join(f'{b},' for b in data)
def normalized(text):return text[1:] if text.startswith('.') else text
bad={'..':'empty','..x':'empty','...':'empty','x..y':'empty','\\':'escape','\\1':'escape','\\12':'escape','\\256':'escape','a'*64:'label','.':'unused-root','.'.join(['a'*63]*4):'name'}

def model(base,ndots,notld,domains):
    encoded=wire(base);dots=base.count('.');absolute=base.endswith('.')
    suffixes=[];issues=[]
    for index,text in enumerate(domains):
        suffix=normalized(text)
        value=None if suffix.startswith('.') else wire(suffix)
        suffixes.append(value)
        if value is None:issues.append(f'issue:{index}:{bad[text]}:{text}')
    def enumerate_all(stop_invalid):
        steps=[];root=False;searched=False;initial=absolute or dots>=ndots
        if initial:steps.append(('initial',encoded))
        if not absolute:
            for index,suffix in enumerate(suffixes):
                searched=True;root |= suffix==b'\0'
                value=None if suffix is None else encoded[:-1]+suffix
                if value is not None and len(value)>255:value=None
                steps.append((f'suffix:{index}',value))
                if value is None and stop_invalid:break
        if not initial and not root and (dots or not searched or not notld):steps.append(('final',encoded))
        return steps
    all_steps=enumerate_all(False);executed=enumerate_all(True)
    status=1 if absolute or dots>=ndots or not executed or executed[-1][1] is not None else 3
    queries=[value for _,value in executed if value is not None]
    want=issues+[origin+':'+csv(value) for origin,value in all_steps]+['END']+['query:'+origin+':'+csv(value) for origin,value in executed if value is not None]+[f'error:{status}']
    return want,queries,status

lists=[[],[''],['.'],['x','y'],['.x','y.'],['..','x'],['x','..','y'],['x','..','.'],['.','..','y'],['..x'],['...'],['x..y'],['\\'],['\\1'],['\\12'],['\\256'],['a'*64,'x'],['.'.join(['a'*63]*4)],['\\000','x'],['\\.','x'],['é.test','x']]
cases=[(base,ndots,notld,domains) for base,ndots,notld,domains in itertools.product(['a','a.b','a.b.',r'a\.b'],[0,2],[0,1],lists)]
cases.append(('a',2,0,['x']*1024))
checks=[]
for backend,command in [('native 1',['build/resolver-domains','--threads','1']),('native 4',['build/resolver-domains','--threads','4']),('Bun',[str(bun),'build/resolver-domains.js'])]:
    for index,(base,ndots,notld,domains) in enumerate(cases):
        want,_,_=model(base,ndots,notld,domains)
        run=subprocess.run([*command,base,str(base.count('.')),str(int(base.endswith('.'))),str(ndots),str(notld),*domains],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,run.stdout[:1000],run.stderr,want[:12])
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} domain preparation/search cases PASS',flush=True)

observations=[]
for base,ndots,notld,domains in cases[:-1]:
    _,expected,status=model(base,ndots,notld,domains);seen=[];done=threading.Event()
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as server,ThreadPoolExecutor(max_workers=1) as pool:
        server.bind(('127.0.0.1',0));server.settimeout(.02)
        def serve():
            while not done.is_set():
                try:packet,peer=server.recvfrom(4096)
                except socket.timeout:continue
                header=struct.unpack('!6H',packet[:12]);assert header[2]==1
                at=12
                while packet[at]:at+=packet[at]+1
                at+=1;seen.append(packet[12:at])
                server.sendto(struct.pack('!6H',header[0],0x8183,1,0,0,0)+packet[12:at+4],peer)
        future=pool.submit(serve)
        try:
            encoded='.' if domains==[''] else '|'.join(domains)
            run=subprocess.run(['build/dns-search-oracle',str(server.getsockname()[1]),base,str(ndots),'1','1',str(notld),encoded],cwd=ROOT,capture_output=True,text=True,timeout=4)
        finally:done.set()
        future.result(timeout=2)
    assert run.returncode==0 and not run.stderr and run.stdout==f'-1,{status}\n' and seen==expected,(base,ndots,notld,domains,run,seen,expected)
    observations.append(dict(base=base,ndots=ndots,notld=notld,domains=domains,queries=[list(q) for q in seen],error=status))
print(f'libc: {len(observations)} loopback query/error sequences PASS',flush=True)
paths=['packages/runtime/src/dns-message.bend','packages/runtime/src/resolver-config.bend','tests/resolver-domains.bend','tests/resolver_domains_check.py','tests/dns-search-oracle.c']
result=dict(scope=__doc__,checks=checks,libc_sequences=observations,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-domains-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-domains-result.json').write_text(json.dumps(result,indent=2)+'\n')
