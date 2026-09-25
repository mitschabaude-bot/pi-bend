"""Address/alias lookup composed with ordered TCP server failover and recovery."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
import errno
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import socket
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);p.add_argument('--no-build',action='store_true');a=p.parse_args()
candidate=a.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
if not a.no_build:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats',f'build/dns-address-servers-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-address-servers.bend','-o',f'build/dns-address-servers.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-address-servers.c','-lpthread','-lm','-o','build/dns-address-servers'],cwd=ROOT,check=True)

def wire(owner):return bytes([len(owner)])+owner.encode()+b'\0'
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
 dict(name='single',servers=['listen'],plan=[(0,'a',0,'address')],answer='a',draws=1),
 dict(name='failover',plan=[(0,'a',0,'eof'),(1,'a',0,'address')],answer='a',draws=1),
 dict(name='refusal',servers=['refused','listen'],plan=[(1,'a',0,'address')],answer='a',draws=1),
 dict(name='alias-after-failover',plan=[(0,'a',0,'eof'),(1,'a',0,'alias:b'),(0,'b',65535,'address')],answer='b',draws=2),
 dict(name='reset-alias-failover',plan=[(0,'a',0,'reset'),(0,'a',0,'alias:b'),(0,'b',65535,'eof'),(1,'b',65535,'address')],answer='b',draws=2),
 dict(name='alias-loop',plan=[(0,'a',0,'eof'),(1,'a',0,'alias:b'),(0,'b',65535,'alias:a')],error='loop',draws=2),
 dict(name='nxdomain',plan=[(0,'a',0,3)],error='rcode:3',draws=1),
 dict(name='empty',plan=[(0,'a',0,'eof'),(1,'a',0,0)],answer='a',empty=True,draws=1),
 dict(name='last-refusal',servers=['listen','refused'],plan=[(0,'a',0,'eof')],error='socket:'+str(errno.ECONNREFUSED),draws=1),
 dict(name='no-servers',servers=[],plan=[],error='no-servers',draws=0),
 dict(name='source-first',mode='error-first',plan=[],error='entropy:11:test source unavailable',draws=1),
 dict(name='source-second',mode='error-second',plan=[(0,'a',0,'alias:b')],error='entropy:38:test source unavailable',draws=2),
 dict(name='pre-abort',mode='pre',plan=[],error='connect:parent',reason='parent',draws=0),
 dict(name='zero',mode='zero',plan=[],error='zero',draws=0),
 dict(name='type',mode='type',plan=[],error='type',draws=0),
 dict(name='deadline-failover',mode='deadline',plan=[(0,'a',0,'slow-eof'),(1,'a',0,'stall')],error='read:expiry',reason='expiry',draws=1),
 dict(name='deadline-alias',mode='deadline',plan=[(0,'a',0,'slow-alias:b'),(0,'b',65535,'stall')],error='read:expiry',reason='expiry',draws=2),
 dict(name='duplicate',order=[0,0],plan=[(0,'a',0,'eof'),(0,'a',0,'address')],answer='a',draws=1),
 dict(name='truncated',plan=[(0,'a',0,'truncated')],error='truncated',draws=1),
]
rows=[]
for backend,command in [('native 1',['build/dns-address-servers','--threads','1']),('native 4',['build/dns-address-servers','--threads','4']),('Bun',[str(bun),'build/dns-address-servers.js'])]:
    for number,family,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for case in cases:
                servers=case.get('servers',['listen','listen']);order=case.get('order',list(range(len(servers))));trace=[]
                with ExitStack() as stack:
                    listeners=[]
                    for state in servers:
                        listener=stack.enter_context(socket.socket(family,socket.SOCK_STREAM));listener.bind((host,0));listener.settimeout(4)
                        if state=='listen':listener.listen(4)
                        listeners.append(listener)
                    pool=stack.enter_context(ThreadPoolExecutor(max_workers=1))
                    def serve():
                        for server,owner,identifier,action in case['plan']:
                            with listeners[server].accept()[0] as peer:
                                peer.settimeout(4)
                                query=exact(peer,struct.unpack('!H',exact(peer,2))[0])
                                assert query==struct.pack('!6H',identifier,256,1,0,0,0)+wire(owner)+struct.pack('!HH',kind,1),(case,query)
                                trace.append([server,owner,identifier])
                                if action in ['slow-eof','slow-alias:b']:time.sleep(.7)
                                if action in ['eof','slow-eof']:continue
                                if action=='reset':
                                    peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));continue
                                if action=='stall':
                                    assert select.select([peer],[],[],.6)[0],'deadline restarted'
                                else:peer.sendall(reply(identifier,owner,kind,'alias:b' if action=='slow-alias:b' else action))
                                assert peer.recv(1)==b'','lookup left an exchange open'
                    future=pool.submit(serve) if case['plan'] else None
                    ports=','.join(str(listeners[i].getsockname()[1]) for i in order)
                    mode=case.get('mode','direct')
                    run=subprocess.run([*command,mode,str(number),ports,str(15 if mode=='type' else kind)],cwd=ROOT,capture_output=True,text=True,timeout=7)
                    if future:future.result(timeout=5)
                    for listener,state in zip(listeners,servers):
                        if state=='listen':assert not select.select([listener],[],[],0)[0],('unexpected lookup',case,run)
                want=[selected(case['answer'],kind,case.get('empty',False)) if 'answer' in case else case['error'],case.get('reason','none'),'draws:'+str(case['draws'])]
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,number,kind,case,run,want)
                rows.append(dict(backend=backend,family=number,kind=kind,case=case,queries=trace,output=want))
    print(f'{backend}: {len(cases)*4} address failover cases PASS',flush=True)
paths=['packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns-address-servers.bend','tests/dns_address_servers_check.py','tests/dns-lookup-ids.bend','tests/dns-address-lookup.bend','tests/dns-tcp-servers.bend','build/dns-address-servers','build/dns-address-servers.js']
r=dict(scope=__doc__,cases=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-address-servers-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-address-servers-result.json').write_text(json.dumps(r,indent=2)+'\n')
