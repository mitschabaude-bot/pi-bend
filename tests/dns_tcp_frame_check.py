"""Incremental DNS TCP framing against a concatenated-byte reference.

Tests framing only; DNS payload syntax and transaction matching are separate.
"""
import argparse
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-build',action='store_true')
args=parser.parse_args()
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-frame-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-tcp-frame.bend','build/dns-tcp-frame'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-tcp-frame-js-build.json','--',str(Path(BEND)),'packages/runtime/test/dns-tcp-frame.bend','-o','build/dns-tcp-frame.js'],cwd=ROOT,check=True)
rng=random.Random(7766);cases=[]
def csv(xs):return ','.join(map(str,xs))
def digest(xs):
    value=2166136261
    for x in xs:value=((value*16777619)^x)&0xffffffff
    return str(len(xs))+','+str(value)
def framed(payload):return list(struct.pack('!H',len(payload)))+list(payload)
def encoded(payload):
    for index,value in enumerate(payload):
        if index==65535:return 'error:long'
        if value>255:return 'error:byte:'+str(value)
    return 'ok:'+digest(framed(payload))
def read(wire):
    invalid=next((i for i,x in enumerate(wire) if x>255),len(wire))
    valid=wire[:invalid];at=0;frames=[]
    while at+2<=len(valid):
        size=(valid[at]<<8)|valid[at+1]
        if at+2+size>len(valid):break
        at+=2;frames.append(digest(valid[at:at+size]));at+=size
    status='byte:'+str(wire[invalid]) if invalid<len(wire) else ('done' if at==len(wire) else 'incomplete')
    return ';'.join(frames)+'|'+status

def reading(chunks):
    wire=[x for chunk in chunks for x in chunk]
    cases.append(('r'+'/'.join(csv(chunk) for chunk in chunks),read(wire)))
for payload in [[],[0],[255],list(range(256)),[256],[4294967295],[1,2,256,3]]:
    cases.append(('e'+csv(payload),encoded(payload)))
for wire in [[],[0],[255],[0,0],[0,1],[0,1,42],[0,1,42,0],[0,1,42,0,0],[1,0]+[0]*255,[1,0]+[0]*256]:
    for split in range(len(wire)+1):reading([wire[:split],[],wire[split:]])
# Every partition of a short stream containing three frames, one empty.
wire=[0,1,42,0,0,0,1,255]
for mask in range(1<<(len(wire)-1)):
    chunks=[];start=0
    for boundary in range(1,len(wire)):
        if mask&(1<<(boundary-1)):chunks.append(wire[start:boundary]);start=boundary
    chunks.append(wire[start:]);reading(chunks)
for _ in range(300):
    payloads=[[rng.randrange(256) for _ in range(rng.randrange(0,180))] for _ in range(rng.randrange(0,6))]
    wire=[x for payload in payloads for x in framed(payload)]
    if rng.randrange(3)==0 and wire:wire=wire[:rng.randrange(len(wire)+1)]
    chunks=[];at=0
    while at<len(wire):
        count=rng.randrange(1,24);chunks.extend([wire[at:at+count],[]]);at+=count
    reading(chunks)
    for payload in payloads:cases.append(('e'+csv(payload),encoded(payload)))
# Invalid bytes at every position: frames already delivered must survive the
# later error, and subsequent chunks must not accidentally reset failure.
wire=framed([1,2,3])+framed([255,0])+framed([])
for index in range(len(wire)+1):
    bad=wire[:index]+[256]+wire[index:]
    reading([bad]);reading([[x] for x in bad])
for count in [0,1,255,256,1024,65534,65535,65536]:
    expected='error:long' if count>65535 else digest([0]*count)+'|done'
    cases.append(('l'+str(count),expected))
backends=[]
for label,command in [('native 1',['build/dns-tcp-frame','--threads','1']),('native 4',['build/dns-tcp-frame','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-tcp-frame.js'])]:
    for first in range(0,len(cases),16):
        batch=cases[first:first+16];result=subprocess.run([*command,*(arg for arg,_ in batch)],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,first,result.stderr)
        lines=result.stdout.splitlines();assert len(lines)==len(batch),(label,first,len(lines),len(batch))
        for index,(got,(arg,want)) in enumerate(zip(lines,batch,strict=True)):
            assert got==want,(label,first+index,arg[:150],got,want)
    print(f'{label}: {len(cases)} DNS TCP frame cases PASS',flush=True);backends.append(label)
paths=[ROOT/'packages/runtime/src/dns-message.bend',ROOT/'packages/runtime/test/dns-tcp-frame.bend',ROOT/'tests/dns_tcp_frame_check.py',ROOT/'build/dns-tcp-frame',ROOT/'build/dns-tcp-frame.js']
(ROOT/'build/dns-tcp-frame-result.json').write_text(json.dumps({'scope':__doc__,'cases_per_backend':len(cases),'backends':backends,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
