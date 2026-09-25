"""Dedicated DNS TCP query with a deadline spanning setup and response handling.

Local Linux IPv4/IPv6 integration; no resolver policy or upstream suite claim.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import shlex
import socket
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);p.add_argument('--no-build',action='store_true');p.add_argument('--build-limit-gib',type=float,default=16);args=p.parse_args()
candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/dns-query-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib',str(args.build_limit_gib),'--stats','build/dns-tcp-query-build.json','--','sh','scripts/build-pure.sh','tests/dns-tcp-query.bend','build/dns-tcp-query'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-query-js-build.json','--',str(launcher),'tests/dns-tcp-query.bend','-o','build/dns-tcp-query.js'],cwd=ROOT,check=True)

def exact(peer,count):
    data=b''
    while len(data)<count:
        part=peer.recv(count-len(data));assert part,'early client EOF';data+=part
    return data

def message(id=42,flags=0x8180):return struct.pack('!6H',id,flags,1,0,0,0)+b'\0\0\1\0\1'
def frame(data):return struct.pack('!H',len(data))+data

rows=[]
for label,command in [('native 1',['build/dns-tcp-query','--threads','1']),('native 4',['build/dns-tcp-query','--threads','4']),('Bun',[str(bun),'build/dns-tcp-query.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
        for mode in ['answer','ignored','truncated','rcode','eof','cut','timeout','noise','parent','pre','pre-default','zero','bad-query','refused']:
            with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host,0));listener.settimeout(3)
                no_connect=mode in ['pre','pre-default','zero','refused']
                if mode!='refused':listener.listen(4)
                def serve():
                    with listener.accept()[0] as peer:
                        peer.settimeout(3)
                        if mode=='bad-query':
                            assert peer.recv(1)==b'';return 0
                        size=struct.unpack('!H',exact(peer,2))[0]
                        assert exact(peer,size)==message(flags=256),'wrong DNS query'
                        if mode in ['answer','ignored','truncated','rcode']:
                            payload=frame(message(flags=0x8380 if mode=='truncated' else (0x8183 if mode=='rcode' else 0x8180)))
                            if mode=='ignored':payload=frame(message(99))+frame(bytes([0,42]))+payload
                            peer.sendall(payload)
                        elif mode=='eof':peer.shutdown(socket.SHUT_WR)
                        elif mode=='cut':peer.sendall(b'\0');peer.shutdown(socket.SHUT_WR)
                        elif mode=='noise':
                            sent=0;deadline=time.monotonic()+2
                            while time.monotonic()<deadline:
                                if select.select([peer],[],[],.01)[0]:
                                    assert peer.recv(1)==b'';assert sent>0;return sent
                                peer.sendall(frame(message(99)));sent+=1
                            raise AssertionError('ignored replies extended the deadline')
                        assert peer.recv(1)==b'','query connection not closed'
                        return 0
                future=None if no_connect else pool.submit(serve)
                started=time.monotonic()
                run=subprocess.run([*command,mode,str(number),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=4)
                elapsed=time.monotonic()-started
                ignored=future.result(timeout=4) if future else 0
                if no_connect and mode!='refused':assert not select.select([listener],[],[],0)[0],'unexpected connection'
                want={'answer':['answer:33152','none'],'ignored':['answer:33152','none'],'truncated':['truncated','none'],'rcode':['answer:33155','none'],'eof':['eof','none'],'cut':['frame','none'],'timeout':['read:expiry','expiry'],'noise':['read:expiry','expiry'],'parent':['read:parent','parent'],'pre':['connect:parent','parent'],'pre-default':['connect:default','default'],'zero':['zero','none'],'bad-query':['query','none'],'refused':['socket:'+str(errno.ECONNREFUSED),'none']}[mode]+['PASS DNS TCP query']
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(label,number,mode,run,want)
                rows.append(dict(backend=label,family=number,mode=mode,seconds=elapsed,ignored_replies=ignored))
        # Saturate the local accept queue and verify that a control connect
        # remains pending before asserting deadline-driven connect cancellation.
        with socket.socket(family,socket.SOCK_STREAM) as listener,socket.socket(family,socket.SOCK_STREAM) as filler,socket.socket(family,socket.SOCK_STREAM) as probe:
            listener.bind((host,0));listener.listen(0)
            filler.settimeout(2);filler.connect(listener.getsockname())
            probe.setblocking(False)
            assert probe.connect_ex(listener.getsockname())==errno.EINPROGRESS
            assert not select.select([],[probe],[],.05)[1]
            probe.close()
            started=time.monotonic()
            run=subprocess.run([*command,'timeout',str(number),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=4)
            assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==['connect:expiry','expiry','PASS DNS TCP query'],(label,number,run)
            rows.append(dict(backend=label,family=number,mode='pending-connect-deadline',seconds=time.monotonic()-started))
    print(label+': DNS TCP deadline query PASS',flush=True)
paths=['packages/runtime/src/dns-transport.bend','packages/runtime/src/deadline.bend','tests/dns-tcp-query.bend','tests/dns_tcp_query_check.py','scripts/prepare-timer-candidate.py','build/dns-tcp-query','build/dns-tcp-query.js']
report={'scope':__doc__,'cases':rows,'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},'candidate_sha256':{p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['base.bend','comp.ts','effs/timer.c','effs/timer.js']}}
(ROOT/'build/dns-tcp-query-result.json').write_text(json.dumps(report,indent=2)+'\n')
