"""Ordered TCP server failover with real loopback endpoints.

One pass; DNS replies are returned without UDP response-code failover. Checks
closed attempts, final error selection, shared deadline and terminal abort.
"""
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
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate',type=Path)
p.add_argument('--no-build',action='store_true')
a=p.parse_args();candidate=a.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
if not a.no_build:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats',f'build/dns-tcp-servers-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-tcp-servers.bend','-o',f'build/dns-tcp-servers.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-tcp-servers.c','-lpthread','-lm','-o','build/dns-tcp-servers'],cwd=ROOT,check=True)

def exact(peer,size):
    data=b''
    while len(data)<size:
        part=peer.recv(size-len(data));assert part,'early EOF';data+=part
    return data

cases=[
    dict(name='refusal-next',servers=['refused',0],outcome='reply:0'),
    dict(name='eof-next',servers=['eof',0],outcome='reply:0'),
    dict(name='partial-next',servers=['partial',0],outcome='reply:0'),
    dict(name='reset-next',servers=['reset',0],outcome='reply:0'),
    dict(name='third-server',servers=['eof','eof',0],outcome='reply:0'),
    dict(name='last-eof',servers=['refused','eof'],outcome='eof'),
    dict(name='last-refusal',servers=['eof','refused'],outcome='socket:'+str(errno.ECONNREFUSED)),
    dict(name='last-partial',servers=['eof','partial'],outcome='frame'),
    dict(name='no-servers',servers=[],outcome='no-servers'),
    dict(name='pre-abort',mode='pre',servers=['unused','unused'],outcome='connect:parent',reason='parent'),
    dict(name='invalid-size',mode='zero',servers=['unused','unused'],outcome='zero'),
    dict(name='deadline',mode='deadline',servers=['slow-eof','stall','unused'],outcome='read:expiry',reason='expiry'),
    dict(name='duplicate-server',servers=['eof',0],order=[0,0],outcome='reply:0'),
    dict(name='truncated',servers=['truncated','unused'],outcome='truncated'),
]
for code in range(16):cases.append(dict(name='rcode-'+str(code),servers=[code,'unused'],outcome='reply:'+str(code)))
rows=[]
for backend,command in [('native 1',['build/dns-tcp-servers','--threads','1']),('native 4',['build/dns-tcp-servers','--threads','4']),('Bun',[str(bun),'build/dns-tcp-servers.js'])]:
    for number,family,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for kind in [1,28]:
            for case in cases:
                types=case['servers'];order=case.get('order',list(range(len(types))));trace=[]
                with ExitStack() as stack:
                    listeners=[]
                    for action in types:
                        listener=stack.enter_context(socket.socket(family,socket.SOCK_STREAM));listener.bind((host,0));listener.settimeout(4)
                        if action!='refused':listener.listen(4)
                        listeners.append(listener)
                    pool=stack.enter_context(ThreadPoolExecutor(max_workers=1))
                    def serve():
                        for index,action in enumerate(types):
                            if action in ['refused','unused']:continue
                            with listeners[order[index]].accept()[0] as peer:
                                peer.settimeout(4)
                                query=exact(peer,struct.unpack('!H',exact(peer,2))[0])
                                question=b'\x01a\0'+struct.pack('!HH',kind,1)
                                assert query==struct.pack('!6H',42,256,1,0,0,0)+question,query
                                trace.append(order[index])
                                if action=='slow-eof':time.sleep(.7);continue
                                if action=='eof':continue
                                if action=='partial':peer.sendall(b'\0');continue
                                if action=='reset':peer.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));continue
                                if action=='stall':
                                    assert select.select([peer],[],[],.6)[0],'server failover restarted deadline'
                                else:
                                    flags=(0x8380 if action=='truncated' else 0x8180|action)
                                    reply=struct.pack('!6H',42,flags,1,0,0,0)+question
                                    peer.sendall(struct.pack('!H',len(reply))+reply)
                                assert peer.recv(1)==b'','attempt left open'
                    future=pool.submit(serve) if any(action not in ['refused','unused'] for action in types) else None
                    ports=','.join(str(listeners[index].getsockname()[1]) for index in order)
                    result=subprocess.run([*command,case.get('mode','direct'),str(number),ports,str(kind)],cwd=ROOT,capture_output=True,text=True,timeout=7)
                    if future:future.result(timeout=5)
                    for index,listener in enumerate(listeners):
                        if types[index]!='refused':assert not select.select([listener],[],[],0)[0],('unexpected attempt',case,index,result)
                want=[case['outcome'],case.get('reason','none')]
                assert result.returncode==0 and not result.stderr and result.stdout.splitlines()==want,(backend,number,kind,case,result,want)
                rows.append(dict(backend=backend,family=number,kind=kind,case=case,accepted_server_indices=trace,output=want))
    print(f'{backend}: {len(cases)*4} TCP failover cases PASS',flush=True)
paths=['packages/runtime/src/dns-tcp-servers.bend','packages/runtime/src/dns-tcp-query.bend','tests/dns-tcp-servers.bend','tests/dns_tcp_servers_check.py','build/dns-tcp-servers','build/dns-tcp-servers.js']
r=dict(scope=__doc__,cases=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-tcp-servers-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-tcp-servers-result.json').write_text(json.dumps(r,indent=2)+'\n')
