"""Local IPv4/IPv6 endpoint-aware DNS TCP response matching.

The peer verifies query bytes, independent endpoint observations and closure.
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
import time

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--no-build',action='store_true')
args=parser.parse_args();candidate=args.candidate.resolve();bun=Path.home()/'.bun/bin/bun'
launcher=ROOT/'build/dns-tcp-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-peer-build.json','--','sh','scripts/build-pure.sh','tests/dns-tcp-peer.bend','build/dns-tcp-peer'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-peer-js-build.json','--',str(launcher),'tests/dns-tcp-peer.bend','-o','build/dns-tcp-peer.js'],cwd=ROOT,check=True)
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-peer-failure-build.json','--','sh','scripts/build-pure.sh','tests/dns-tcp-peer-failure.bend','build/dns-tcp-peer-failure'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-peer-failure-js-build.json','--',str(launcher),'tests/dns-tcp-peer-failure.bend','-o','build/dns-tcp-peer-failure.js'],cwd=ROOT,check=True)
def exact(peer,count):
    data=b''
    while len(data)<count:
        part=peer.recv(count-len(data));assert part,'early client EOF';data+=part
    return data
def message(id,flags,question=True,kind=1):return struct.pack('!6H',id,flags,int(question),0,0,0)+(b'\0'+struct.pack('!HH',kind,1) if question else b'')
def frame(data):return struct.pack('!H',len(data))+data
def endpoint(value):
    import ipaddress
    ip=ipaddress.ip_address(value[0]);raw=int(ip)
    words=[raw,0,0,0] if ip.version==4 else [(raw>>shift)&0xffffffff for shift in [96,64,32,0]]
    return ','.join(map(str,[ip.version,*words,value[1],value[3] if ip.version==6 else 0]))
results=[]
for label,command in [('native 1',['build/dns-tcp-peer','--threads','1']),('native 4',['build/dns-tcp-peer','--threads','4']),('Bun',[str(bun),'build/dns-tcp-peer.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
        for mode in ['matched','absent','wrong-id','wrong-question','truncated','malformed','abort']:
            with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host,0));listener.listen(8);listener.settimeout(15)
                def serve():
                    with listener.accept()[0] as peer:
                        peer.settimeout(15)
                        local,remote=peer.getsockname(),peer.getpeername()
                        if mode!='abort':
                            for id in [1,2]:
                                size=struct.unpack('!H',exact(peer,2))[0]
                                assert exact(peer,size)==message(id,256),'wrong query frame'
                            first=message(2,33152)
                            if mode=='absent':first=message(2,33152,False)
                            elif mode=='wrong-id':first=message(99,33152)
                            elif mode=='wrong-question':first=message(2,33152,kind=28)
                            elif mode=='truncated':first=message(2,33664)
                            elif mode=='malformed':first=b'\0\2'
                            peer.sendall(frame(first)+frame(message(1,33152)));peer.shutdown(socket.SHUT_WR)
                        assert peer.recv(1)==b'','client did not terminate the connection'
                        return local,remote
                future=pool.submit(serve)
                result=subprocess.run([*command,mode,str(number),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=25)
                server,client=future.result(timeout=20)
                first={'matched':'matched:2','absent':'matched:2','wrong-id':'id','wrong-question':'question','truncated':'truncated','malformed':'malformed'}
                expected=['PASS DNS TCP peer'] if mode=='abort' else [endpoint(client),endpoint(server),first[mode],'matched:1','PASS DNS TCP peer']
                assert result.returncode==0 and result.stdout.splitlines()==expected and not result.stderr,(label,number,mode,result,expected)
                results.append(dict(backend=label,family=number,mode=mode))
    print(label+': DNS TCP peer cases PASS',flush=True)
for label,command in [('native 1',['build/dns-tcp-peer-failure','--threads','1']),('native 4',['build/dns-tcp-peer-failure','--threads','4']),('Bun',[str(bun),'build/dns-tcp-peer-failure.js'])]:
    run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=20)
    assert run.returncode==0 and run.stdout=='PASS DNS TCP peer inspection cleanup\n' and not run.stderr,(label,run)
    results.append(dict(backend=label,mode='inspection failure releases bound UDP port',iterations=32))
    print(label+': inspection cleanup PASS',flush=True)
paths=[ROOT/'tests/dns-tcp-peer-failure.bend',ROOT/'build/dns-tcp-peer-failure',ROOT/'build/dns-tcp-peer-failure.js',ROOT/'packages/runtime/src/dns-transport.bend',ROOT/'tests/dns-tcp-peer.bend',ROOT/'tests/dns_tcp_peer_check.py',candidate/'comp.ts',candidate/'base.bend',ROOT/'build/dns-tcp-peer',ROOT/'build/dns-tcp-peer.js']
(ROOT/'build/dns-tcp-peer-result.json').write_text(json.dumps({'scope':__doc__,'cases':results,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
