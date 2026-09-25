"""Offline DNS transaction matching contracts (RFC 5452 and RFC 4343).

Endpoint metadata is supplied by the fixture; this is not socket integration.
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
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-response-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-response.bend','build/dns-response'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-response-js-build.json','--',str(Path(BEND)),'packages/runtime/test/dns-response.bend','-o','build/dns-response.js'],cwd=ROOT,check=True)
rng=random.Random(5452);cases=[]
def csv(xs):return ','.join(map(str,xs))
def name(labels):return bytes([b for label in labels for b in [len(label),*label]]+[0])
def question(labels,kind=1,klass=1):return name(labels)+struct.pack('!HH',kind,klass)
def wire(labels=(b'Example',b'COM'),id=42,flags=0x8180,qd=1,an=0,ns=0,ar=0,kind=1,klass=1,tail=b''):
    return struct.pack('!6H',id,flags,qd,an,ns,ar)+question(labels,kind,klass)+tail
query=wire(flags=256)
def add(response,expected,mode=0,sent=query):
    cases.append((str(mode)+':'+csv(sent)+':'+csv(response),expected))
for mode in range(13):
    add(wire(),'matched:33152' if mode<2 else 'ignore:endpoint',mode)
    add(wire(flags=0x8380,an=1),'truncated:33664' if mode<2 else 'ignore:endpoint',mode)
# Mismatched metadata is rejected without requiring the packet to parse.
for mode in range(2,13):add([], 'ignore:endpoint', mode)
for id in [0,1,42,32768,65535]:
    sent=wire(id=id,flags=256)
    add(wire(id=id),'matched:33152',sent=sent)
    add(wire(id=(id+1)%65536),'ignore:id',sent=sent)
for opcode in range(16):
    sent=wire(flags=opcode<<11)
    add(wire(flags=0x8000|(opcode<<11)), 'matched:'+str(0x8000|(opcode<<11)),sent=sent)
    add(wire(flags=0x8000|(((opcode+1)%16)<<11)),'ignore:opcode',sent=sent)
    add(wire(flags=opcode<<11),'ignore:query',sent=sent)
for code in range(16):
    for extra in [0,0x0100,0x0400,0x0080,0x0020,0x0010,0x0040]:
        flags=0x8000|code|extra
        add(wire(flags=flags),'matched:'+str(flags))
for count in [0,2,65535]:
    for flags in [0x8180,0x8380]:add(wire(qd=count,flags=flags),'ignore:count')
for kind in [0,1,28,255,65535]:
    for klass in [0,1,3,255,65535]:
        sent=wire(kind=kind,klass=klass,flags=256)
        add(wire(kind=kind,klass=klass),'matched:33152',sent=sent)
        add(wire(kind=(kind+1)%65536,klass=klass),'ignore:question',sent=sent)
        add(wire(kind=kind,klass=(klass+1)%65536),'ignore:question',sent=sent)
# bytes.lower is independently ASCII-only: test every byte against itself,
# its ASCII-folded value and the next byte, preserving binary label boundaries.
for value in range(256):
    sent=wire(labels=[bytes([value])],flags=256)
    for other in [value,bytes([value]).lower()[0],(value+1)%256]:
        equal=bytes([value]).lower()==bytes([other]).lower()
        add(wire(labels=[bytes([other])]),'matched:33152' if equal else 'ignore:question',sent=sent)
for left,right in [([b'ab',b'c'],[b'a',b'bc']),([b'a.b'],[b'a',b'b']),([],[b'a']),([b'\0a'],[b'a']),([b'\xdd'],[b'\xfd'])]:
    add(wire(labels=right),'ignore:question',sent=wire(labels=left,flags=256))
for _ in range(200):
    labels=[bytes(rng.randrange(256) for _ in range(rng.randrange(1,30))) for _ in range(rng.randrange(0,5))]
    altered=[bytes(x+32 if 65<=x<=90 else x for x in label) for label in labels]
    add(wire(labels=altered),'matched:33152',sent=wire(labels=labels,flags=256))
# Truncation is acted on only after the full question has matched. TC permits
# missing/incomplete record sections; the same bytes without TC are malformed.
for counts in [(1,0,0),(0,1,0),(0,0,1),(65535,65535,65535)]:
    for tail in [b'',b'\xc0',b'\xc0\x0c\0\1',b'\xff'*9]:
        add(wire(flags=0x8380,an=counts[0],ns=counts[1],ar=counts[2],tail=tail),'truncated:33664')
        add(wire(an=counts[0],ns=counts[1],ar=counts[2],tail=tail),'ignore:malformed')
        add(wire(flags=0x8380,an=counts[0],labels=[b'other'],tail=tail),'ignore:question')
for length in range(len(query)):
    add(wire()[:length],'ignore:malformed')
    add(wire(flags=0x8380)[:length],'ignore:malformed')
add(wire()+b'\0','ignore:malformed')
add(wire(flags=0x8380)+b'\0','truncated:33664')
# A structurally complete matching answer is retained, including compressed
# owner names; record trust and address selection are deliberately later.
answer=b'\xc0\x0c'+struct.pack('!HHIH',1,1,300,4)+b'\x7f\0\0\1'
add(wire(an=1,tail=answer),'matched:33152')
# The established-stream policy retains every existing endpoint/header/question
# rejection, but permits QDCOUNT=0. All present-question baseline cases are
# repeated through the stream entry point.
for arg,expected in list(cases):
    if expected == 'ignore:count': continue
    mode,sent,reply=arg.split(':')
    cases.append((str(int(mode)+100)+':'+sent+':'+reply,expected))
for flags in [0x8000,0x8180,0x8183,0x8380]:
    empty=struct.pack('!6H',42,flags,0,0,0,0)
    want=('truncated:' if flags&512 else 'matched:')+str(flags)
    for mode in range(13):
        add(empty,want if mode<2 else 'ignore:endpoint',100+mode)
        add(empty,'ignore:count' if mode<2 else 'ignore:endpoint',mode)
    add(empty+b'\0','truncated:'+str(flags) if flags&512 else 'ignore:malformed',100)
    add(struct.pack('!6H',43,flags,0,0,0,0),'ignore:id',100)
    add(struct.pack('!6H',42,flags^0x8000,0,0,0,0),'ignore:query',100)
    add(struct.pack('!6H',42,flags|0x0800,0,0,0,0),'ignore:opcode',100)
owner=name([b'example',b'com'])
record=owner+struct.pack('!HHIH',1,1,300,4)+b'\x7f\0\0\1'
for length in range(len(record)+1):
    reply=struct.pack('!6H',42,0x8180,0,1,0,0)+record[:length]
    add(reply,'matched:33152' if length==len(record) else 'ignore:malformed',100)
    truncated=struct.pack('!6H',42,0x8380,0,1,0,0)+record[:length]
    add(truncated,'truncated:33664',100)
for count in [2,65535]:add(wire(qd=count),'ignore:count',100)
backends=[]
for label,command in [('native 1',['build/dns-response','--threads','1']),('native 4',['build/dns-response','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-response.js'])]:
    for first in range(0,len(cases),16):
        batch=cases[first:first+16];result=subprocess.run([*command,*(arg for arg,_ in batch)],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,first,result.stderr)
        actual=result.stdout.splitlines();assert len(actual)==len(batch),(label,first,len(actual),len(batch))
        for index,(got,(arg,want)) in enumerate(zip(actual,batch,strict=True)):
            assert got==want,(label,first+index,arg[:150],got,want)
    print(f'{label}: {len(cases)} DNS response matching cases PASS',flush=True);backends.append(label)
paths=[ROOT/'packages/runtime/src/dns-message.bend',ROOT/'packages/runtime/test/dns-response.bend',ROOT/'tests/dns_response_check.py',ROOT/'build/dns-response',ROOT/'build/dns-response.js']
(ROOT/'build/dns-response-result.json').write_text(json.dumps({'scope':__doc__,'cases_per_backend':len(cases),'backends':backends,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
