"""Reusable TCP resolver configuration, per-call deadlines and owner replacement."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
import errno
import hashlib
import json
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path);p.add_argument('--no-build',action='store_true');a=p.parse_args()
candidate=a.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
if not a.no_build:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','20','--stats',f'build/dns-resolver-lookup-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-resolver-lookup.bend','-o',f'build/dns-resolver-lookup.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-resolver-lookup.c','-lpthread','-lm','-o','build/dns-resolver-lookup'],cwd=ROOT,check=True)

def wire(owner):return b''.join(bytes([len(label)])+label.encode() for label in owner.rstrip('.').split('.'))+b'\0'
def exact(peer,size):
    data=b''
    while len(data)<size:
        part=peer.recv(size-len(data));assert part,'early EOF';data+=part
    return data

def reply(identifier,owner,kind,action):
    flags=0x8380 if action=='truncated' else 0x8180|(action if isinstance(action,int) else 0)
    count=0;record=b''
    if action=='address':
        data=bytes(range(1,5 if kind==1 else 17));count=1
        record=wire(owner)+struct.pack('!HHIH',kind,1,60,len(data))+data
    if isinstance(action,str) and action.startswith('alias:'):
        data=wire(action[6:]);count=1
        record=wire(owner)+struct.pack('!HHIH',5,1,60,len(data))+data
    data=struct.pack('!6H',identifier,flags,1,count,0,0)+wire(owner)+struct.pack('!HH',kind,1)+record
    return struct.pack('!H',len(data))+data

def selected(owner,kind,empty=False):
    return 'ok:'+''.join(str(x)+',' for x in wire(owner))+':'+('' if empty else ('4,16909060,60;' if kind==1 else '6,16909060,84281096,151653132,219025168,60;'))

cases=[
 dict(name='invalid-domain',mode='invalid-domain',plan=[(1,'a',0,'address'),(2,'b',65535,'address')],first='a',second='b',draws=2),
 dict(name='invalid-later',mode='invalid-later',plan=[(1,'a.x',0,3),(2,'a',65535,'address'),(0,'b.x',4660,'address')],first='a',second='b.x',draws=3),
 dict(name='rotate',plan=[(1,'a.x',0,'address'),(2,'b.x',65535,'address')],first='a.x',second='b.x',draws=2),
 dict(name='fixed',mode='fixed',plan=[(0,'a.x',0,'address'),(0,'b.x',65535,'address')],first='a.x',second='b.x',draws=2),
 dict(name='suffix',plan=[(1,'a.x',0,3),(2,'a.y',65535,'address'),(0,'b.x',4660,'address')],first='a.y',second='b.x',draws=3),
 dict(name='alias',plan=[(1,'a.x',0,'alias:c'),(2,'c',65535,'address'),(0,'b.x',4660,'address')],first='c',second='b.x',draws=3),
 dict(name='failover',plan=[(1,'a.x',0,'eof'),(2,'a.x',0,'address'),(2,'b.x',65535,'address')],first='a.x',second='b.x',draws=2),
 dict(name='reset',plan=[(1,'a.x',0,'reset'),(1,'a.x',0,'address'),(2,'b.x',65535,'address')],first='a.x',second='b.x',draws=2),
 dict(name='absolute',mode='absolute',plan=[(1,'a',0,'address'),(2,'b',65535,'address')],first='a',second='b',draws=2),
 dict(name='deadline',mode='deadline',plan=[(1,'a.x',0,'stall'),(2,'b.x',65535,'address')],error='read:expiry',reason='expiry',second='b.x',draws=2),
 dict(name='empty',servers=0,plan=[],error='no-servers',second_error='no-servers',draws=0),
 dict(name='type',kind=15,plan=[],error='type',second_error='type',draws=0),
]
rows=[]
for backend,command in [('native 1',['build/dns-resolver-lookup','--threads','1']),('native 4',['build/dns-resolver-lookup','--threads','4']),('Bun',[str(bun),'build/dns-resolver-lookup.js'])]:
    for number,family,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for case_index,case in enumerate(cases):
                trace=[]
                with ExitStack() as stack:
                    listeners=[]
                    for _ in range(case.get('servers',3)):
                        listener=stack.enter_context(socket.socket(family,socket.SOCK_STREAM));listener.bind((host,0));listener.listen(4);listener.settimeout(5);listeners.append(listener)
                    pool=stack.enter_context(ThreadPoolExecutor(max_workers=1))
                    def serve():
                        for server,owner,identifier,action in case['plan']:
                            with listeners[server].accept()[0] as peer:
                                peer.settimeout(5)
                                query=exact(peer,struct.unpack('!H',exact(peer,2))[0])
                                assert query==struct.pack('!6H',identifier,256,1,0,0,0)+wire(owner)+struct.pack('!HH',kind,1),(case,query)
                                trace.append([server,owner,identifier])
                                if action=='eof':continue
                                if action=='reset':
                                    peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));continue
                                if action=='stall':assert select.select([peer],[],[],1)[0],'deadline not applied'
                                else:peer.sendall(reply(identifier,owner,kind,action))
                                assert peer.recv(1)==b'','resolver left exchange open'
                    future=pool.submit(serve) if case['plan'] else None
                    ports=','.join(str(sock.getsockname()[1]) for sock in listeners)
                    run=subprocess.run([*command,case.get('mode','rotate'),str(number),ports,str(case.get('kind',kind))],cwd=ROOT,capture_output=True,text=True,timeout=7)
                    if future:future.result(timeout=5)
                    for listener in listeners:assert not select.select([listener],[],[],0)[0],('unexpected lookup',case)
                want=[case['error'] if 'error' in case else selected(case['first'],kind),'none',case.get('reason','none'),case['second_error'] if 'second_error' in case else selected(case['second'],kind),'none','none','draws:'+str(case['draws'])]
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,number,kind,case,run,want)
                rows.append(dict(backend=backend,family=number,kind=kind,case=case_index,queries=trace,output=want))
    print(backend+f': {len(cases)*4} reused resolver scenarios PASS',flush=True)
paths=['packages/runtime/src/dns-tcp-resolver.bend','tests/dns-resolver-lookup.bend','tests/dns_resolver_check.py','build/dns-resolver-lookup','build/dns-resolver-lookup.js']
r=dict(scope=__doc__,cases=cases,runs=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-resolver-lookup-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-resolver-result.json').write_text(json.dumps(r,indent=2)+'\n')
