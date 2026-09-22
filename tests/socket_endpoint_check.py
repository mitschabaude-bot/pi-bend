"""Observe local/peer numeric endpoints and retain working socket ownership.

Linux IPv4, IPv6 and IPv4-mapped TCP peers plus an unconnected UDP socket.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import ipaddress
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--no-build',action='store_true')
args=parser.parse_args();candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/endpoint-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/socket-endpoint-build.json','--','sh','scripts/build-pure.sh','tests/socket-endpoint.bend','build/socket-endpoint'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/socket-endpoint-js-build.json','--',str(launcher),'tests/socket-endpoint.bend','-o','build/socket-endpoint.js'],cwd=ROOT,check=True)
def endpoint(host,port,mapped=False):
    address=ipaddress.ip_address(('::ffff:'+host) if mapped else host)
    if address.version==4:return [4,int(address),0,0,0,port,0]
    raw=int(address)
    return [6,*[(raw>>shift)&0xffffffff for shift in [96,64,32,0]],port,0]
results=[]
for label,command in [('native 1',['build/socket-endpoint','--threads','1']),('native 4',['build/socket-endpoint','--threads','4']),('Bun',[str(bun),'build/socket-endpoint.js'])]:
    for mode,family,host in [('4',socket.AF_INET,'127.0.0.1'),('6',socket.AF_INET6,'::1'),('mapped',socket.AF_INET,'127.0.0.1')]:
        with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
            listener.bind((host,0));listener.listen(8);listener.settimeout(15)
            def serve():
                with listener.accept()[0] as peer:
                    peer.settimeout(15)
                    local=peer.getsockname();remote=peer.getpeername()
                    for _ in range(16):
                        assert peer.recv(1)==b'*';peer.sendall(b'+')
                    assert peer.recv(1)==b''
                    return local,remote
            future=pool.submit(serve)
            result=subprocess.run([*command,mode,str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=25)
            server,client=future.result(timeout=20)
            assert result.returncode==0 and not result.stderr,(label,mode,result)
            lines=result.stdout.splitlines();assert lines[-1]=='PASS socket endpoint' and len(lines)==33,(label,mode,lines)
            want=[endpoint(client[0],client[1],mode=='mapped'),endpoint(server[0],server[1],mode=='mapped')]*16
            got=[list(map(int,line.split(','))) for line in lines[:-1]]
            assert got==want,(label,mode,got,want)
            results.append(dict(backend=label,mode=mode,iterations=16,local=want[0],peer=want[1]))
    result=subprocess.run([*command,'udp',str(errno.ENOTCONN)],cwd=ROOT,capture_output=True,text=True,timeout=20)
    assert result.returncode==0 and not result.stderr,(label,result)
    lines=result.stdout.splitlines();assert len(lines)==3 and lines[-1]=='PASS socket endpoint'
    first=list(map(int,lines[0].split(',')));assert lines[0]==lines[1]
    assert first[:5]==[4,0,0,0,0] and 0<first[5]<=65535 and first[6]==0,first
    results.append(dict(backend=label,mode='unconnected UDP',endpoint=first,peer_error=errno.ENOTCONN))
    print(label+': endpoint ownership/metadata PASS',flush=True)
paths=[ROOT/'packages/runtime/src/socket-endpoint.bend',ROOT/'tests/socket-endpoint.bend',ROOT/'tests/socket_endpoint_check.py',candidate/'comp.ts',candidate/'base.bend',candidate/'effs/socket_endpoint.c',candidate/'effs/socket_endpoint.js',ROOT/'build/socket-endpoint',ROOT/'build/socket-endpoint.js']
(ROOT/'build/socket-endpoint-result.json').write_text(json.dumps({'scope':__doc__,'cases':results,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
