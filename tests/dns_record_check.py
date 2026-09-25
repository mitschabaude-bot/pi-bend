"""Typed DNS IN record decoding, independent binary reference and message composition.

RFC 1035 record layouts and RFC 3596 network-order AAAA format. No network IO.
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
parser.add_argument('--baseline-js',type=Path,help='Optional retained nested-dispatch program for equivalent-output checks')
args=parser.parse_args()
if not args.no_build:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-record-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-record.bend','build/dns-record'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-record-js-build.json','--',str(Path(BEND)),'packages/runtime/test/dns-record.bend','-o','build/dns-record.js'],cwd=ROOT,check=True)
rng=random.Random(3596);cases=[]
def csv(xs): return ','.join(map(str,xs))
def text(labels): return '/'.join(csv(label) for label in labels)
def wire_name(labels): return bytes([x for label in labels for x in [len(label),*label]]+[0])

def name(wire,position):
    visited=set();labels=[];end=None;size=1
    while True:
        if position>=len(wire) or position in visited: raise ValueError()
        visited.add(position);tag=wire[position];position+=1
        if tag==0:return labels,position if end is None else end
        if tag<64:
            size+=tag+1
            if size>255 or position+tag>len(wire):raise ValueError()
            labels.append(wire[position:position+tag]);position+=tag
        elif tag>=192:
            if position>=len(wire):raise ValueError()
            target=((tag&63)<<8)|wire[position];position+=1
            if target>=position-2:raise ValueError()
            if end is None:end=position
            position=target
        else:raise ValueError()

def reference(wire,kind,klass,start,length,owner=(),ttl=123):
    if any(x>255 for x in wire):return 'packet-error'
    if start>len(wire) or length>len(wire)-start:return 'error'
    if klass!=1 or kind not in [1,28,5,2,12,6]:return 'opaque:'+text(owner)+':'+csv([kind,klass,ttl,start,length])
    end=start+length
    try:
        if kind==1:
            if length!=4:raise ValueError()
            return 'A:'+str(int.from_bytes(bytes(wire[start:end]),'big'))
        if kind==28:
            if length!=16:raise ValueError()
            return 'AAAA:'+csv(struct.unpack('!4I',bytes(wire[start:end])))
        first,next_at=name(wire,start)
        if kind!=6:
            if next_at!=end:raise ValueError()
            return {5:'CNAME:',2:'NS:',12:'PTR:'}[kind]+text(first)
        second,next_at=name(wire,next_at)
        if next_at+20!=end:raise ValueError()
        return 'SOA:'+text(first)+':'+text(second)+':'+csv(struct.unpack('!5I',bytes(wire[next_at:end])))
    except (ValueError,struct.error):return 'error'

def add(wire,kind,klass=1,start=0,length=None):
    if length is None:length=len(wire)-start
    cases.append(('r'+':'.join(map(str,[kind,klass,start,length]))+':'+csv(wire),reference(wire,kind,klass,start,length)))

for number in [0,1,255,256,65535,65536,2147483648,4294967295]:add(struct.pack('!I',number),1)
for _ in range(200):
    add(struct.pack('!I',rng.randrange(1<<32)),1)
    add(struct.pack('!4I',*(rng.randrange(1<<32) for _ in range(4))),28)
for kind in [1,28]:
    for length in range(0,35):add(bytes(range(length)),kind)
for _ in range(200):
    labels=[[rng.randrange(256) for _ in range(rng.randrange(1,30))] for _ in range(rng.randrange(0,5))]
    encoded=wire_name(labels)
    for kind in [2,5,12]:
        add(encoded,kind)
        add(encoded+b'\xc0\0',kind,start=len(encoded))
    mailbox=[[rng.randrange(256) for _ in range(rng.randrange(1,20))]]
    tail=struct.pack('!5I',*(rng.choice([0,1,4294967295,rng.randrange(1<<32)]) for _ in range(5)))
    add(encoded+wire_name(mailbox)+tail,6)
    add(encoded+b'\xc0\0'+b'\xc0\0'+tail,6,start=len(encoded))
# Every prefix and one surplus byte around structured data, including cases
# where following bytes exist in the packet but are outside declared RDATA.
soa=wire_name([b'ns',b'example'])+wire_name([b'hostmaster',b'example'])+struct.pack('!5I',1,2,3,4,5)
for length in range(len(soa)+1):
    add(soa[:length],6)
    add(soa,6,length=length)
add(soa+b'\0',6)
for kind in [2,5,12]:
    for wire in [b'',b'\xc0',b'\xc0\0',b'\xc0\2\0',b'\x40',b'\x80',b'\x01a',b'\0\0',wire_name([b'a'])*2]:add(wire,kind)
    for length in range(6):add(wire_name([b'abc'])+b'\0',kind,length=length)
# Unknown kind/class never invents an address interpretation.
for kind in [0,1,2,5,6,12,16,28,41,65535]:
    for klass in [0,1,3,255,65535]:
        add(bytes(range(17)),kind,klass)
for start,length in [(0,0),(1,0),(2,0),(0,2),(4294967295,1),(1,4294967295)]:
    for kind in [1,5,6,65535]:add(b'\0',kind,start=start,length=length)
add([256],1)
# One real parsed message carries each typed record in answers and a retained
# opaque record in additional. Names point back to the question at offset 12.
owner=[b'example',b'com'];question=wire_name(owner)+struct.pack('!HH',1,1)
records=[(1,1,b'\x7f\0\0\1'),(28,1,bytes(range(16))),(5,1,b'\xc0\x0c'),(2,1,b'\xc0\x0c'),(12,1,b'\xc0\x0c'),(6,1,b'\xc0\x0c\xc0\x0c'+struct.pack('!5I',1,2,3,4,5)),(65535,3,b'\xff\0\xc0')]
wire=bytearray(struct.pack('!6H',42,0x8180,1,6,0,1)+question);expected=[]
for kind,klass,data in records:
    wire+=b'\xc0\x0c'+struct.pack('!HHIH',kind,klass,300,len(data));start=len(wire);wire+=data
    expected.append(reference(wire,kind,klass,start,len(data),owner,300))
cases.append(('m'+csv(wire),'|'.join(expected[:6])+';;'+expected[6]))
backends=[]
commands=[('native 1',['build/dns-record','--threads','1']),('native 4',['build/dns-record','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-record.js'])]
if args.baseline_js: commands.append(('Bun nested baseline',[str(Path.home()/'.bun/bin/bun'),str(args.baseline_js.resolve())]))
for label,command in commands:
    for first in range(0,len(cases),16):
        batch=cases[first:first+16];result=subprocess.run([*command,*(arg for arg,_ in batch)],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,first,result.stderr)
        lines=result.stdout.splitlines();assert len(lines)==len(batch),(label,first,len(lines),len(batch))
        for index,(got,(arg,want)) in enumerate(zip(lines,batch,strict=True)):
            assert got==want,(label,first+index,arg[:150],got,want)
    print(f'{label}: {len(cases)} typed DNS record cases PASS',flush=True);backends.append(label)
paths=[ROOT/'packages/runtime/src/dns-message.bend',ROOT/'packages/runtime/test/dns-record.bend',ROOT/'tests/dns_record_check.py',ROOT/'build/dns-record',ROOT/'build/dns-record.js']
if args.baseline_js: paths.append(args.baseline_js.resolve())
(ROOT/'build/dns-record-result.json').write_text(json.dumps({'scope':__doc__,'cases_per_backend':len(cases),'backends':backends,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
