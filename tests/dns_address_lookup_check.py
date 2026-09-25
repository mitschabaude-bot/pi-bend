"""Local recursive-server address lookups across deadline-bounded TCP exchanges.

Checks both query address families and both server socket families. No OS
resolver configuration, cache, retry or query-ID entropy claim.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
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
launcher=ROOT/'build/dns-lookup-compiler';launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(bun))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_build:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib',str(args.build_limit_gib),'--stats','build/dns-address-lookup-build.json','--','sh','scripts/build-pure.sh','tests/dns-address-lookup.bend','build/dns-address-lookup'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-address-lookup-js-build.json','--',str(launcher),'tests/dns-address-lookup.bend','-o','build/dns-address-lookup.js'],cwd=ROOT,check=True)
def exact(peer,count):
    data=b''
    while len(data)<count:
        part=peer.recv(count-len(data));assert part,'early EOF';data+=part
    return data

def name(value):return bytes([len(value)])+value+b'\0'
def question(value,kind):return name(value)+struct.pack('!HH',kind,1)
def record(owner,kind,data):return name(owner)+struct.pack('!HHIH',kind,1,60,len(data))+data
def cname(owner,target):return record(owner,5,name(target))
def address(owner,kind):return record(owner,kind,bytes(range(1,5 if kind==1 else 17)))
def message(owner,kind,answers,flags=0x8180):return struct.pack('!6H',42,flags,1,len(answers),0,0)+question(owner,kind)+b''.join(answers)
def frame(data):return struct.pack('!H',len(data))+data

def selected(owner,kind,present=True):
    fields=[4,0x01020304,60] if kind==1 else [6,0x01020304,0x05060708,0x090a0b0c,0x0d0e0f10,60]
    return 'ok:'+''.join(str(x)+',' for x in name(owner))+':'+(','.join(map(str,fields))+';' if present else '')
chain=[b'a']+[('n'+str(i)).encode() for i in range(1,33)]
rows=[]
for label,command in [('native 1',['build/dns-address-lookup','--threads','1']),('native 4',['build/dns-address-lookup','--threads','4']),('Bun',[str(bun),'build/dns-address-lookup.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
      for kind in [1,28]:
        for mode in ['direct','inline','aliases','long','cycle','empty','alias-empty','rcode','truncated','deadline','pre','zero','type']:
            with socket.socket(family,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host,0));listener.listen(8);listener.settimeout(3)
                no_connect=mode in ['pre','zero','type']
                plan={
                    'direct':[(b'a',[address(b'a',kind)],0x8180)],
                    'long':[(chain[i],[cname(chain[i],chain[i+1])],0x8180) for i in range(len(chain)-1)]+[(chain[-1],[address(chain[-1],kind)],0x8180)],
                    'inline':[(b'a',[address(b'c',kind),cname(b'b',b'c'),cname(b'a',b'b')],0x8180)],
                    'aliases':[(b'a',[cname(b'a',b'b')],0x8180),(b'b',[cname(b'b',b'c')],0x8180),(b'c',[address(b'c',kind)],0x8180)],
                    'cycle':[(b'a',[cname(b'a',b'b'),cname(b'b',b'c')],0x8180),(b'c',[cname(b'c',b'b'),address(b'b',kind)],0x8180)],
                    'empty':[(b'a',[],0x8180)],
                    'alias-empty':[(b'a',[cname(b'a',b'b')],0x8180),(b'b',[],0x8180)],
                    'rcode':[(b'a',[cname(b'a',b'b')],0x8180),(b'b',[],0x8183)],
                    'truncated':[(b'a',[],0x8380)],
                    'deadline':[(b'a',[cname(b'a',b'b')],0x8180),(b'b',[],0x8180)],
                }.get(mode,[])
                def serve():
                    asked=[]
                    for index,(owner,answers,flags) in enumerate(plan):
                      with listener.accept()[0] as peer:
                        peer.settimeout(3)
                        length=struct.unpack('!H',exact(peer,2))[0]
                        query=exact(peer,length)
                        assert query==struct.pack('!6H',42,256,1,0,0,0)+question(owner,kind),query
                        asked.append(owner.decode())
                        if mode=='deadline' and index==0:time.sleep(.7)
                        if mode=='deadline' and index==1:
                            # Only ~300 ms of the original second remains. A
                            # new 1 s deadline here would violate this bound.
                            assert select.select([peer],[],[],.6)[0],'deadline restarted on alias follow-up'
                        else:peer.sendall(frame(message(owner,kind,answers,flags)))
                        assert peer.recv(1)==b'','exchange not closed before next request'
                    return asked
                future=None if no_connect else pool.submit(serve)
                run=subprocess.run([*command,mode,str(number),str(listener.getsockname()[1]),str(15 if mode=='type' else kind)],cwd=ROOT,capture_output=True,text=True,timeout=4)
                asked=future.result(timeout=4) if future else []
                assert not select.select([listener],[],[],0)[0],'unexpected extra connection'
                result={'direct':selected(b'a',kind),'inline':selected(b'c',kind),'aliases':selected(b'c',kind),'long':selected(chain[-1],kind),'cycle':'loop','empty':selected(b'a',kind,False),'alias-empty':selected(b'b',kind,False),'rcode':'rcode:3','truncated':'truncated','deadline':'read:expiry','pre':'connect:parent','zero':'zero','type':'type'}[mode]
                reason='expiry' if mode=='deadline' else ('parent' if mode=='pre' else 'none')
                want=[result,reason,'PASS DNS address lookup']
                assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(label,number,kind,mode,run,want)
                rows.append(dict(backend=label,server_family=number,query_type=kind,mode=mode,questions=asked))
    print(label+': address lookup PASS',flush=True)
paths=['packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-resolver.bend','packages/runtime/src/dns-transport.bend','tests/dns-address-lookup.bend','tests/dns_address_lookup_check.py','build/dns-address-lookup','build/dns-address-lookup.js']
(ROOT/'build/dns-address-lookup-result.json').write_text(json.dumps({'scope':__doc__,'cases':rows,'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},'candidate_sha256':{p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['base.bend','comp.ts']}},indent=2)+'\n')
