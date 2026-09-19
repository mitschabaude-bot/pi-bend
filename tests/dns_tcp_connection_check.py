"""Local IPv4/IPv6 DNS framing over owned cancellable TCP sockets.

Uses unchanged generated programs; socket metadata/transaction dispatch are
not integrated here. The peer verifies query bytes and observes termination.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shlex
import socket
import struct
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path)
parser.add_argument('--no-build',action='store_true')
args=parser.parse_args();candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/dns-tcp-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-connection-build.json','--','sh','scripts/build-pure.sh','tests/dns-tcp-connection.bend','build/dns-tcp-connection'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-connection-js-build.json','--',str(launcher),'tests/dns-tcp-connection.bend','-o','build/dns-tcp-connection.js'],cwd=ROOT,check=True)
def exact(peer,count):
    data=b''
    while len(data)<count:
        part=peer.recv(count-len(data));assert part,'early client EOF';data+=part
    return data
def message(id,flags):return struct.pack('!6H',id,flags,1,0,0,0)+b'\0\0\1\0\1'
def frame(data):return struct.pack('!H',len(data))+data
results=[]
for label,command in [('native 1',['build/dns-tcp-connection','--threads','1']),('native 4',['build/dns-tcp-connection','--threads','4']),('Bun',[str(bun),'build/dns-tcp-connection.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
        for mode in ['pipeline','one-byte','cut-prefix','cut-body','abort','buffered']:
            with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host,0));listener.listen(8);listener.settimeout(15)
                def serve():
                    with listener.accept()[0] as peer:
                        peer.settimeout(15)
                        count=3 if mode in ['pipeline','one-byte'] else 1
                        for id in range(1,count+1):
                            size=struct.unpack('!H',exact(peer,2))[0]
                            assert size==17,(mode,size)
                            assert exact(peer,size)==message(id,256),'wrong query frame'
                        if mode in ['pipeline','one-byte']:
                            response=b''.join(frame(message(id,33152)) for id in [3,2,1])
                            peer.sendall(response[:1]);time.sleep(.005);peer.sendall(response[1:]);peer.shutdown(socket.SHUT_WR)
                        elif mode=='cut-prefix':peer.sendall(b'\0');peer.shutdown(socket.SHUT_WR)
                        elif mode=='cut-body':peer.sendall(frame(message(1,33152))[:8]);peer.shutdown(socket.SHUT_WR)
                        # Abort modes deliberately withhold response bytes. The
                        # buffered mode installs a deterministic test-only suffix.
                        assert peer.recv(1)==b'','client did not terminate the connection'
                future=pool.submit(serve)
                result=subprocess.run([*command,mode,str(number),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=25)
                future.result(timeout=20)
                assert result.returncode==0 and result.stdout=='PASS DNS TCP connection\n' and not result.stderr,(label,number,mode,result)
                results.append(dict(backend=label,family=number,mode=mode))
    print(label+': DNS TCP connection cases PASS',flush=True)
paths=[ROOT/'packages/runtime/src/dns-tcp-connection.bend',ROOT/'tests/dns-tcp-connection.bend',ROOT/'tests/dns_tcp_connection_check.py',candidate/'comp.ts',candidate/'base.bend',ROOT/'build/dns-tcp-connection',ROOT/'build/dns-tcp-connection.js']
(ROOT/'build/dns-tcp-connection-result.json').write_text(json.dumps({'scope':__doc__,'cases':results,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
