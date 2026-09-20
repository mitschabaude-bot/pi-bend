"""Immutable server rotation and libc first-server sequence comparison.

The libc random initial position is observed, then used to align the Bend
state. This validates subsequent rotation/disable behavior, not random seeding.
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
import hashlib
import itertools
import json
from pathlib import Path
import platform
import select
import socket
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-server-rotation-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/dns-server-rotation.bend','-o',f'build/dns-server-rotation.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-server-rotation.c','-lpthread','-lm','-o','build/dns-server-rotation'],cwd=ROOT,check=True)
subprocess.run(['cc','-O2','tests/dns-rotation-oracle.c','-lresolv','-o','build/dns-rotation-oracle'],cwd=ROOT,check=True)
commands=[('native 1',['build/dns-server-rotation','--threads','1']),('native 4',['build/dns-server-rotation','--threads','4']),('Bun',[str(bun),'build/dns-server-rotation.js'])]
def encoded(values):return ','.join(map(str,values))
def rendered(values):return ''.join(str(value)+',' for value in values)
def model(values,flags):
    original=values[:];current=values[:];rows=[]
    for flag in flags:
        rows.append(rendered(current if flag=='1' else original))
        if flag=='1' and current:current=current[1:]+current[:1]
    return rows

lists=[[],[0],[0,1],[0,1,2],[0,1,2,3],[9,9,7],[4294967295,0,4294967295]]
cases=[(values,''.join(flags)) for values in lists for flags in itertools.product('01',repeat=8)]
cases += [(list(range(16384)),'101011'),([0,1,2],'101'*3334),([0,1],'')]
checks=[]
for backend,command in commands:
    for start in range(0,len(cases),32):
        batch=cases[start:start+32];args=[arg for values,flags in batch for arg in [encoded(values),flags]]
        expected=[line for values,flags in batch for line in model(values,flags)]
        run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==expected,(backend,start,run.returncode,run.stderr,run.stdout[:100])
    checks.append(dict(backend=backend,cases=len(cases),selections=sum(len(flags) for _,flags in cases)))
    print(f'{backend}: {len(cases)} rotation sequences PASS',flush=True)

def exact(peer,size):
    data=b''
    while len(data)<size:
        part=peer.recv(size-len(data));assert part,'early EOF';data+=part
    return data

libc=[]
for count in [1,2,3]:
    for flags in ['1'*24,'001011001101010011010111','0'*24]:
        with ExitStack() as stack:
            listeners=[]
            for _ in range(count):
                listener=stack.enter_context(socket.socket(socket.AF_INET,socket.SOCK_STREAM));listener.bind(('127.0.0.1',0));listener.listen(4);listeners.append(listener)
            pool=stack.enter_context(ThreadPoolExecutor(max_workers=1))
            observed=[]
            def serve():
                for _ in flags:
                    ready=select.select(listeners,[],[],4)[0];assert len(ready)==1,ready
                    selected=ready[0];observed.append(listeners.index(selected))
                    with selected.accept()[0] as peer:
                        peer.settimeout(4)
                        query=exact(peer,struct.unpack('!H',exact(peer,2))[0])
                        expected=struct.pack('!6H',42,256,1,0,0,0)+b'\0\0\1\0\1'
                        assert query==expected,query
                        answer=struct.pack('!6H',42,0x8180,1,0,0,0)+expected[12:]
                        peer.sendall(struct.pack('!H',len(answer))+answer)
                        assert peer.recv(1)==b'','libc did not close query socket'
            future=pool.submit(serve)
            run=subprocess.run(['build/dns-rotation-oracle',flags,*[str(listener.getsockname()[1]) for listener in listeners]],cwd=ROOT,capture_output=True,text=True,timeout=30)
            future.result(timeout=5)
            assert run.returncode==0 and not run.stderr and run.stdout=='PASS libc rotation\n',run
        initial=observed[flags.index('1')] if '1' in flags else 0
        warmup='1'*initial
        for backend,command in commands:
            run=subprocess.run([*command,encoded(list(range(count))),warmup+flags],cwd=ROOT,capture_output=True,text=True,timeout=15)
            assert run.returncode==0 and not run.stderr,(backend,run)
            choices=[int(row.split(',')[0]) for row in run.stdout.splitlines()[initial:]]
            assert choices==observed,(backend,count,flags,initial,choices,observed)
        libc.append(dict(servers=count,flags=flags,initial=initial,first_servers=observed))
print('9 libc loopback sequences / 216 queries PASS',flush=True)
paths=['packages/runtime/src/dns-server-rotation.bend','tests/dns-server-rotation.bend','tests/dns_server_rotation_check.py','tests/dns-rotation-oracle.c','build/dns-server-rotation','build/dns-server-rotation.js']
r=dict(scope=__doc__,checks=checks,libc=libc,libc_version=platform.libc_ver(),sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-server-rotation-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((compiler/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-server-rotation-result.json').write_text(json.dumps(r,indent=2)+'\n')
