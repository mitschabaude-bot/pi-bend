"""Linux IPv4/IPv6 pipelined DNS session dispatch and pending-request settlement.

Real sockets, unchanged generated programs. No exhaustive race/resource audit.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import socket
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);p.add_argument('--no-build',action='store_true');p.add_argument('--build-limit-gib',type=float,default=8);args=p.parse_args()
candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/dns-session-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib',str(args.build_limit_gib),'--stats','build/dns-tcp-session-build.json','--','sh','scripts/build-pure.sh','tests/dns-tcp-session.bend','build/dns-tcp-session'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-session-js-build.json','--',str(launcher),'tests/dns-tcp-session.bend','-o','build/dns-tcp-session.js'],cwd=ROOT,check=True)

def exact(peer,count):
    data=b''
    while len(data)<count:
        part=peer.recv(count-len(data));assert part,'early client EOF';data+=part
    return data

def message(id,flags=0x8180):return struct.pack('!6H',id,flags,1,0,0,0)+b'\0\0\1\0\1'
def edns_message(id):
    header=struct.pack('!6H',id,256,1,0,0,1)
    data=struct.pack('!HH',65001,2)+b'\x00\xff'+struct.pack('!HH',65001,0)
    return header+b'\0\0\1\0\1'+b'\0'+struct.pack('!HHIH',41,1232,32768,len(data))+data

def frame(data):return struct.pack('!H',len(data))+data

def normalized(line):
    if line.startswith(('ended:','closed:')):
        head,tail=line.rsplit(':',1)
        return head+':'+','.join(map(str,sorted(int(x) for x in tail.split(',') if x)))
    return line

rows=[]
for label,command in [('native 1',['build/dns-tcp-session','--threads','1']),('native 4',['build/dns-tcp-session','--threads','4']),('Bun',[str(bun),'build/dns-tcp-session.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
        for mode in ['replies','truncated','eof','cut','abort','write-abort','close','cancel','edns']:
            with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host,0));listener.listen(4);listener.settimeout(15)
                def serve():
                    with listener.accept()[0] as peer:
                        peer.settimeout(15)
                        for id in ([1] if mode=='write-abort' else [1,2]):
                            size=struct.unpack('!H',exact(peer,2))[0]
                            assert exact(peer,size)==(edns_message(id) if mode=='edns' else message(id,256)),'unexpected query'
                        if mode in ['replies','truncated']:
                            peer.sendall(b''.join(frame(x) for x in [b'\0\2',message(99),message(2,0x8380 if mode=='truncated' else 0x8180),message(1)]))
                            peer.shutdown(socket.SHUT_WR)
                        elif mode in ['cancel','edns']:
                            peer.sendall(frame(message(1)))
                            size=struct.unpack('!H',exact(peer,2))[0]
                            assert exact(peer,size)==message(1,256),'missing reused-ID request'
                            peer.sendall(frame(message(2))+frame(message(1)));peer.shutdown(socket.SHUT_WR)
                        elif mode=='eof':peer.shutdown(socket.SHUT_WR)
                        elif mode=='cut':peer.sendall(b'\0');peer.shutdown(socket.SHUT_WR)
                        assert peer.recv(1)==b'','duplicate, invalid or stopped query reached the wire'
                future=pool.submit(serve)
                run=subprocess.run([*command,mode,str(number),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=25)
                future.result(timeout=20)
                if mode in ['replies','truncated']:want=['submitted','submitted','duplicate','query','zero','ignored','ignored',('truncated:2' if mode=='truncated' else 'answer:2'),'answer:1','ended:eof:','ended:eof:','stopped','closed:']
                elif mode=='eof':want=['submitted','submitted','ended:eof:1,2','ended:eof:','stopped','closed:']
                elif mode=='abort':want=['submitted','submitted','ended:abort:1,2','ended:abort:','ended:abort:','stopped','closed:']
                elif mode=='cut':want=['submitted','submitted','ended:framing:1,2','ended:framing:','stopped','closed:']
                elif mode=='write-abort':want=['submitted','ended:abort:1,2','ended:abort:','ended:abort:','stopped','closed:']
                elif mode=='cancel':want=['submitted','submitted','cancel:1','ignored','submitted','cancel:none','answer:2','answer:1','ended:eof:','ended:eof:','stopped','closed:']
                elif mode=='edns':want=['submitted','duplicate','extension:field','extension:byte:256','query','ticket:2:1','cancel:1','ignored','submitted','cancel:none','answer:2','answer:1','ended:eof:','stopped','closed:']
                else:want=['submitted','submitted','closed:1,2']
                want.append('PASS DNS TCP session')
                assert run.returncode==0 and not run.stderr and list(map(normalized,run.stdout.splitlines()))==want,(label,number,mode,run,want)
                rows.append(dict(backend=label,family=number,mode=mode,events=want))
    print(label+': DNS TCP session PASS',flush=True)
paths=['packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns-tcp-session.bend','tests/dns_tcp_session_check.py','build/dns-tcp-session','build/dns-tcp-session.js']
report={'scope':__doc__,'cases':rows,'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},'candidate_sha256':{p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['base.bend','comp.ts']}}
(ROOT/'build/dns-tcp-session-result.json').write_text(json.dumps(report,indent=2)+'\n')
