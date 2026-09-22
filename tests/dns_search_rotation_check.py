"""Owned per-question server rotation through search, aliases and retries."""
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
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats',f'build/dns-search-rotation-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-search-rotation.bend','-o',f'build/dns-search-rotation.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search-rotation.c','-lpthread','-lm','-o','build/dns-search-rotation'],cwd=ROOT,check=True)

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
 dict(name='suffixes',plan=[(0,'a.x',0,3),(1,'a.y',65535,'address')],answer='a.y',draws=2,steps=2),
 dict(name='alias',plan=[(0,'a.x',0,'alias:b'),(1,'b',65535,'address')],answer='b',draws=2,steps=2),
 dict(name='suffix-alias',plan=[(0,'a.x',0,3),(1,'a.y',65535,'alias:b'),(2,'b',4660,'address')],answer='b',draws=3,steps=3),
 dict(name='failover',plan=[(0,'a.x',0,'eof'),(1,'a.x',0,3),(1,'a.y',65535,'address')],answer='a.y',draws=2,steps=2),
 dict(name='reset',plan=[(0,'a.x',0,'reset'),(0,'a.x',0,3),(1,'a.y',65535,'address')],answer='a.y',draws=2,steps=2),
 dict(name='alias-failover',plan=[(0,'a.x',0,'alias:b'),(1,'b',65535,'eof'),(2,'b',65535,'address')],answer='b',draws=2,steps=2),
 dict(name='temporary-final',plan=[(0,'a.x',0,'eof'),(1,'a.x',0,'eof'),(2,'a.x',0,'eof'),(1,'a',65535,'address')],answer='a',draws=2,steps=2),
 dict(name='wrapped-final-order',plan=[(0,'a.x',0,3),(1,'a.y',65535,3),(2,'a',4660,'eof'),(0,'a',4660,'eof'),(1,'a',4660,'address')],answer='a',draws=3,steps=3),
 dict(name='source-first',mode='error-first',plan=[],error='entropy:11:test source unavailable',draws=1,steps=0),
 dict(name='source-second',mode='error-second',plan=[(0,'a.x',0,3)],error='entropy:38:test source unavailable',draws=2,steps=1),
 dict(name='pre-abort',mode='pre',plan=[],error='connect:parent',reason='parent',draws=0,steps=0),
 dict(name='no-servers',servers=[],plan=[],error='no-servers',draws=0,steps=0),
 dict(name='zero',mode='zero',plan=[],error='zero',draws=0,steps=0),
 dict(name='type',mode='type',plan=[],error='type',draws=0,steps=0),
 dict(name='invalid-name',text='a..b',ndots=1,plan=[],dns=3,draws=0,steps=0),
 dict(name='disabled',mode='disabled',plan=[(0,'a.x',0,3),(0,'a.y',65535,'address')],answer='a.y',draws=2,steps=0),
 dict(name='deadline-suffix',mode='deadline',slow_first=True,plan=[(0,'a.x',0,3),(1,'a.y',65535,'stall')],error='read:expiry',reason='expiry',draws=2,steps=2),
 dict(name='deadline-alias-reset',mode='deadline',slow_first=True,plan=[(0,'a.x',0,'alias:b'),(1,'b',65535,'reset'),(1,'b',65535,'stall')],error='read:expiry',reason='expiry',draws=2,steps=2),
 dict(name='singleton',servers=['listen'],plan=[(0,'a.x',0,3),(0,'a.y',65535,'address')],answer='a.y',draws=2,steps=0),
]

rows=[]
for backend,command in [('native 1',['build/dns-search-rotation','--threads','1']),('native 4',['build/dns-search-rotation','--threads','4']),('Bun',[str(bun),'build/dns-search-rotation.js'])]:
    for number,family,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for case_index,case in enumerate(cases):
                servers=case.get('servers',['listen','listen','listen']);order=case.get('order',list(range(len(servers))));trace=[]
                with ExitStack() as stack:
                    listeners=[]
                    for state in servers:
                        listener=stack.enter_context(socket.socket(family,socket.SOCK_STREAM));listener.bind((host,0));listener.settimeout(4)
                        if state=='listen':listener.listen(4)
                        listeners.append(listener)
                    pool=stack.enter_context(ThreadPoolExecutor(max_workers=1))
                    def serve():
                        for attempt,(server,owner,identifier,action) in enumerate(case['plan']):
                            with listeners[server].accept()[0] as peer:
                                peer.settimeout(4)
                                query=exact(peer,struct.unpack('!H',exact(peer,2))[0])
                                assert query==struct.pack('!6H',identifier,256,1,0,0,0)+wire(owner)+struct.pack('!HH',kind,1),(case,query)
                                trace.append([server,owner,identifier])
                                if case.get('slow_first') and attempt==0:time.sleep(.7)
                                if action in ['eof','slow-eof']:continue
                                if action=='reset':
                                    peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));continue
                                if action=='stall':
                                    assert select.select([peer],[],[],.6)[0],'deadline restarted'
                                else:peer.sendall(reply(identifier,owner,kind,'alias:b' if action=='slow-alias:b' else action))
                                assert peer.recv(1)==b'','lookup left an exchange open'
                    future=pool.submit(serve) if case['plan'] else None
                    port_values=[listeners[i].getsockname()[1] for i in order]
                    ports=','.join(map(str,port_values))
                    mode=case.get('mode','direct')
                    text=case.get('text','a')
                    run=subprocess.run([*command,mode,str(number),ports,str(15 if mode=='type' else kind),text,str(text.count('.')),str(int(text.endswith('.'))),str(case.get('ndots',2)),case.get('domains','x|y')],cwd=ROOT,capture_output=True,text=True,timeout=7)
                    if future:future.result(timeout=5)
                    for listener,state in zip(listeners,servers):
                        if state=='listen':assert not select.select([listener],[],[],0)[0],('unexpected lookup',case,run)
                if 'dns' in case:want=['dns:'+str(case['dns'])]
                else:want=[selected(case['answer'],kind) if 'answer' in case else case['error'],'none']
                offset=case['steps']%len(port_values) if port_values else 0
                following=port_values[offset:]+port_values[:offset]
                want += [case.get('reason','none'),'next:'+''.join(str(port)+',' for port in following),'draws:'+str(case['draws'])]
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,number,kind,case,run,want)
                rows.append(dict(backend=backend,family=number,kind=kind,case=case_index,queries=trace,output=want))
    print(f'{backend}: {len(cases)*4} rotating search cases PASS',flush=True)
paths=['packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns-search-rotation.bend','tests/dns_search_rotation_check.py','tests/dns-lookup-ids.bend','tests/dns-address-lookup.bend','tests/dns-tcp-servers.bend','build/dns-search-rotation','build/dns-search-rotation.js']
r=dict(scope=__doc__,cases=cases,runs=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-search-rotation-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-search-rotation-result.json').write_text(json.dumps(r,indent=2)+'\n')
