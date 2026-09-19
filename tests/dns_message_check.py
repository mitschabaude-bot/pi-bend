"""DNS message structure and query encoding against an independent byte parser.

RFC 1035 section 4.1. This tests wire structure, not resolver acceptance policy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-build',action='store_true')
args=parser.parse_args()
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-message-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-message.bend','build/dns-message'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-message-js-build.json','--',str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/dns-message.bend','-o','build/dns-message.js'],cwd=ROOT,check=True)
rng=random.Random(41035); cases=[]

def csv(values): return ','.join(map(str,values))
def name_text(labels): return '/'.join(csv(label) for label in labels)
def wire_name(labels): return bytes([x for label in labels for x in [len(label),*label]]+[0])

class Invalid(Exception): pass

def name(packet,start):
    at=start; next_at=None; seen=set(); labels=[]; expanded=1
    while True:
        if at>=len(packet): raise Invalid('name:Truncated')
        if at in seen: raise Invalid('name:InvalidPointer')
        seen.add(at); tag=packet[at];at+=1
        if tag==0: return labels, at if next_at is None else next_at
        if tag<64:
            expanded+=1+tag
            if expanded>255: raise Invalid('name:NameTooLong')
            if at+tag>len(packet): raise Invalid('name:Truncated')
            labels.append(packet[at:at+tag]);at+=tag
        elif tag>=192:
            if at>=len(packet): raise Invalid('name:Truncated')
            target=((tag&63)<<8)|packet[at];at+=1
            if target>=at-2: raise Invalid('name:InvalidPointer')
            if next_at is None: next_at=at
            at=target
        else: raise Invalid('name:ReservedLabel')

def parse(packet):
    try:
        if len(packet)>65535: raise Invalid('name:PacketTooLong')
        if any(x>255 for x in packet): raise Invalid('name:InvalidByte')
        packet=bytes(packet)
        if len(packet)<12: raise Invalid('Truncated')
        header=struct.unpack_from('!6H',packet); at=12; sections=[]
        for section,count in enumerate(header[2:]):
            entries=[]
            for _ in range(count):
                labels,at=name(packet,at)
                if section==0:
                    if at+4>len(packet): raise Invalid('Truncated')
                    kind,klass=struct.unpack_from('!HH',packet,at);at+=4
                    entries.append(name_text(labels)+':'+csv([kind,klass]))
                else:
                    if at+10>len(packet): raise Invalid('Truncated')
                    kind,klass,ttl,length=struct.unpack_from('!HHIH',packet,at);at+=10
                    if at+length>len(packet): raise Invalid('Truncated')
                    entries.append(name_text(labels)+':'+csv([kind,klass,ttl,at,length]));at+=length
            sections.append(';'.join(entries))
        if at!=len(packet): raise Invalid('TrailingData')
        return 'ok:'+csv(header)+'|'+'|'.join(sections)
    except Invalid as error: return 'error:'+str(error)

def parsing(packet): cases.append(('p'+csv(packet),parse(packet)))

def query(id,flags,kind,klass,labels):
    arg='q'+':'.join([str(id),str(flags),str(kind),str(klass),name_text(labels)])
    if any(n>65535 for n in [id,flags,kind,klass]): expected='error:InvalidField'
    elif any(not 1<=len(label)<=63 for label in labels): expected='error:name:InvalidLabel'
    elif any(x>255 for label in labels for x in label): expected='error:name:InvalidByte'
    elif sum(len(label)+1 for label in labels)+1>255: expected='error:name:NameTooLong'
    else:
        wire=struct.pack('!6H',id,flags,1,0,0,0)+wire_name(labels)+struct.pack('!HH',kind,klass)
        expected='ok:'+csv(wire);parsing(wire)
    cases.append((arg,expected))

for value in [0,1,255,256,65535,65536,4294967295]:
    for field in range(4):
        fields=[123,256,1,1];fields[field]=value
        query(*fields,[[65,0,255],[99,111,109]])
for labels in [[],[[],[]],[[1]*63],[[1]*64],[[256]],[[1]*63]*3+[[2]*61],[[1]*63]*4]: query(42,256,28,1,labels)
for _ in range(100):
    labels=[[rng.randrange(256) for _ in range(rng.randrange(1,25))] for _ in range(rng.randrange(1,5))]
    query(*(rng.randrange(65536) for _ in range(4)),labels)
# Unknown kinds/classes, arbitrary flags and full 32-bit TTLs are wire values,
# not rejected merely because the eventual resolver may not consume them.
for _ in range(200):
    counts=[rng.randrange(1,4),rng.randrange(0,5),rng.randrange(0,5),rng.randrange(0,5)]
    wire=bytearray(struct.pack('!6H',rng.randrange(65536),rng.randrange(65536),*counts))
    labels=[[rng.randrange(256) for _ in range(rng.randrange(1,15))] for _ in range(rng.randrange(1,4))]
    for index in range(counts[0]):
        wire+=wire_name(labels) if index==0 else b'\xc0\x0c'
        wire+=struct.pack('!HH',rng.randrange(65536),rng.randrange(65536))
    for count in counts[1:]:
        for _ in range(count):
            data=bytes(rng.randrange(256) for _ in range(rng.randrange(0,50)))
            wire+=rng.choice([b'\0',b'\xc0\x0c',wire_name(labels)])
            wire+=struct.pack('!HHIH',rng.choice([1,5,28,41,65535]),rng.randrange(65536),rng.choice([0,1,2147483648,4294967295]),len(data))+data
    parsing(wire)
# A compressed CNAME retains its two-byte span, including its packet-relative
# pointer. Later record-specific decoding must use this original packet.
example=struct.pack('!6H',42,0x8180,1,2,1,1)+wire_name([b'example',b'com'])+struct.pack('!HH',1,1)
for kind,data in [(5,b'\xc0\x0c'),(1,b'\x7f\0\0\1'),(2,b'\xc0\x0c'),(28,bytes(range(16)))]:
    example+=b'\xc0\x0c'+struct.pack('!HHIH',kind,1,300,len(data))+data
for length in range(len(example)+1): parsing(example[:length])
parsing(example+b'\0')
for index in [4,6,8,10]:
    malformed=bytearray(example);malformed[index:index+2]=b'\xff\xff';parsing(malformed)
for length in range(12): parsing(bytes(length))
for flags in [0,0x0200,0x8000,0xffff]: parsing(struct.pack('!6H',0,flags,0,0,0,0))
for suffix in [b'\xc0',b'\xc0\x0c',b'\xc0\x0e\0',b'\x40',b'\x80',b'\x01a',b'\0\0\1']:
    parsing(struct.pack('!6H',0,0,1,0,0,0)+suffix)
parsing([0]*12+[256])
# Long section and many zero-length unknown records exercise order and counts.
parsing(struct.pack('!6H',1,0x8180,0,256,0,0)+b''.join(b'\0'+struct.pack('!HHIH',i,1,i,0) for i in range(256)))
for _ in range(300):
    parsing([rng.randrange(256) for _ in range(rng.randrange(0,100))])
backends=[]
for label,command in [('native 1',['build/dns-message','--threads','1']),('native 4',['build/dns-message','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-message.js'])]:
    for first in range(0,len(cases),16):
        batch=cases[first:first+16]
        result=subprocess.run([*command,*(arg for arg,_ in batch)],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(label,first,result.stderr)
        lines=result.stdout.splitlines(); assert len(lines)==len(batch),(label,first,len(lines),len(batch))
        for offset,(got,(arg,want)) in enumerate(zip(lines,batch,strict=True)):
            assert got==want,(label,first+offset,arg[:150],got,want)
    print(f'{label}: {len(cases)} DNS message cases PASS',flush=True);backends.append(label)
paths=[ROOT/'packages/runtime/src/dns-message.bend',ROOT/'packages/runtime/test/dns-message.bend',ROOT/'tests/dns_message_check.py',ROOT/'build/dns-message',ROOT/'build/dns-message.js']
(ROOT/'build/dns-message-result.json').write_text(json.dumps({'scope':__doc__,'cases_per_backend':len(cases),'backends':backends,'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
