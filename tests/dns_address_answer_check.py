"""Pure address-answer selection against an independent record-set model.

Generated DNS packets include binary names, aliases, section separation and
malformed relevant RDATA. This is not a complete stub resolver or DNSSEC test.
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
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--no-build',action='store_true');args=p.parse_args()
if not args.no_build:subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-address-answer-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-address-answer.bend','build/dns-address-answer'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-address-answer-js-build.json','--',str(Path(BEND)),'packages/runtime/test/dns-address-answer.bend','-o','build/dns-address-answer.js'],cwd=ROOT,check=True)

def name(labels):return b''.join(bytes([len(x)])+x for x in labels)+b'\0'
def fold(labels):return tuple(x.lower() for x in labels)
def rr(owner,kind,data,ttl=60,klass=1):return dict(owner=tuple(owner),kind=kind,data=data,ttl=ttl,klass=klass)
def alias(owner,target,ttl=60):return rr(owner,5,name(target),ttl)
def target(data,query):
    if data==b'\xc0\x0c':return tuple(query)
    labels=[];i=0
    while i<len(data):
        size=data[i];i+=1
        if size==0:
            if i!=len(data):raise ValueError()
            return tuple(labels)
        if size>63 or i+size>len(data):raise ValueError()
        labels.append(data[i:i+size]);i+=size
    raise ValueError()

def expected(query,kind,answers,rcode):
    if rcode:return 'rcode:'+str(rcode)
    if kind not in [1,28]:return 'type'
    groups={}
    for r in answers:
        if r['klass']==1:groups.setdefault(fold(r['owner']),[]).append(r)
    current=tuple(query);seen=set()
    while True:
        key=fold(current)
        if key in seen:return 'loop'
        seen.add(key);canonical=None;addresses=[];has_address=False
        for r in groups.get(key,[]):
            if r['kind'] in [1,28]:has_address=True
            if r['kind']==5:
                try:new=target(r['data'],query)
                except ValueError:return 'record'
                if canonical is not None and fold(canonical)!=fold(new):return 'conflict'
                if canonical is None:canonical=new
            elif r['kind']==kind:
                size=4 if kind==1 else 16
                if len(r['data'])!=size:return 'record'
                words=struct.unpack('!'+('I' if kind==1 else '4I'),r['data'])
                addresses.append(','.join(map(str,[4 if kind==1 else 6,*words,r['ttl']]))+';')
        if canonical is not None:
            if has_address:return 'conflict'
            current=canonical;continue
        return 'ok:'+''.join(str(x)+',' for x in name(current))+':'+''.join(addresses)

cases=[]
def add(query,kind,answers,authority=(),additional=(),rcode=0,extension_error=False):
    def encode(r):
        owner=b'\xc0\x0c' if r['owner']==tuple(query) else name(r['owner'])
        return owner+struct.pack('!HHIH',r['kind'],r['klass'],r['ttl'],len(r['data']))+r['data']
    packet=struct.pack('!6H',42,0x8180|(rcode & 15),1,len(answers),len(authority),len(additional))+name(query)+struct.pack('!HH',kind,1)+b''.join(encode(r) for section in [answers,authority,additional] for r in section)
    cases.append((str(kind)+':'+','.join(map(str,packet)),'extension' if extension_error else expected(query,kind,answers,rcode)))

q=(b'Example',b'COM');end=(b'Target',b'COM');v4=bytes([1,2,3,4]);v6=bytes(range(16))
for kind,data in [(1,v4),(28,v6)]:
    for ttl in [0,1,0x7fffffff,0x80000000,0xffffffff]:
        add(q,kind,[rr(q,kind,data,ttl),rr(q,kind,data,ttl)])
    add(q,kind,[])
    add(q,kind,[rr(q,kind,data,klass=3)])
    add(q,kind,[],[rr(q,kind,data)],[rr(q,kind,data)])
    add(q,kind,[alias(q,end),rr(end,kind,data)])
    add(q,kind,[rr(end,kind,data),alias(q,end)])
    add(q,kind,[alias(q,end)],additional=[rr(end,kind,data)])
    add(q,kind,[alias(q,end),alias(q,tuple(x.lower() for x in end)),rr(end,kind,data)])
    add(q,kind,[alias(q,end),alias(q,(b'other',)),rr(end,kind,data)])
    add(q,kind,[alias(q,end),rr(q,kind,data)])
    add(q,kind,[rr(q,28 if kind==1 else 1,v6 if kind==1 else v4),alias(q,end)])
    add(q,kind,[alias(q,q)])
    add(q,kind,[alias(q,end),alias(end,q)])
    add(q,kind,[rr(q,5,b'\xc0\x0c')])
    for n in range(18):add(q,kind,[rr(q,kind,bytes(range(n)))])
    for bad in [b'',b'\x03ab',b'\x40',name(end)+b'\0']:
        add(q,kind,[rr(q,5,bad)])
        add(q,kind,[rr((b'unrelated',),5,bad),rr(q,kind,data)])
    for code in range(1,16):add(q,kind,[rr(q,kind,data)],rcode=code)
for kind in [0,5,15,255,65535]:add(q,kind,[])
for value in range(256):
    binary=(bytes([value]),b'X')
    add(binary,1,[rr(tuple(x.lower() for x in binary),1,v4)])
for left,right in [((b'ab',b'c'),(b'a',b'bc')),((b'a.b',),(b'a',b'b')),((b'\0a',),(b'a',)),((),(b'root',))]:
    add(left,1,[rr(right,1,v4)])
    add(left,1,[alias(left,right),rr(right,1,v4)])
for depth in [1,2,16,64,128,512]:
    labels=[(str(i).encode(),b'chain') for i in range(depth+1)]
    chain=[alias(labels[i],labels[i+1]) for i in range(depth)]
    add(labels[0],1,list(reversed(chain))+[rr(labels[-1],1,v4)])
    add(labels[0],1,chain+[alias(labels[-1],labels[0])])
# Many identical self-alias records must not make cycle detection rescan the
# same record set once per available fuel step.
add(q,1,[alias(q,q)]*1000)
rng=random.Random(1034)
for _ in range(500):
    kind=rng.choice([1,28]);depth=rng.randrange(8)
    labels=[(bytes(rng.randrange(256) for _ in range(rng.randrange(1,15))),b'example') for i in range(depth+1)]
    answer=[alias(labels[i],labels[i+1],rng.randrange(0x100000000)) for i in range(depth)]
    for _ in range(rng.randrange(1,5)):answer.append(rr(labels[-1],kind,rng.randbytes(4 if kind==1 else 16),rng.randrange(0x100000000)))
    answer.extend([rr((b'noise',),kind,b'bad'),rr(labels[-1],16,b'ignored')]);rng.shuffle(answer)
    add(labels[0],kind,answer)
# A matching address must never hide an extended DNS error. Lower nibbles
# include zero (BADVERS) and ordinary retry/search error codes.
for kind,data in [(1,v4),(28,v6)]:
    for upper in [0,1,2,255]:
        for low in [0,2,3,15]:
            for version in [0,1,255]:
                opt=rr((),41,b'',ttl=(upper<<24)|(version<<16)|65535,klass=1232)
                add(q,kind,[rr(q,kind,data)],additional=[opt],rcode=upper*16+low)
    opt=rr((),41,b'',klass=1232)
    for additional in [[opt,opt],[rr(q,41,b'',klass=1232)],[rr((),41,b'\0\1\0\1',klass=1232)]]:
        add(q,kind,[rr(q,kind,data)],additional=additional,extension_error=True)
    add(q,kind,[rr(q,kind,data),opt],extension_error=True)
    add(q,kind,[rr(q,kind,data)],authority=[opt],extension_error=True)
    # Unknown and duplicate options do not affect address extraction.
    add(q,kind,[rr(q,kind,data)],additional=[rr((),41,b'\xfd\xe9\0\1\xff\xfd\xe9\0\0',klass=1)])
rows=[]
for label,command in [('native 1',['build/dns-address-answer','--threads','1']),('native 4',['build/dns-address-answer','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-address-answer.js'])]:
    for start in range(0,len(cases),20):
        batch=cases[start:start+20]
        run=subprocess.run([*command,*[x[0] for x in batch]],cwd=ROOT,capture_output=True,text=True,timeout=45)
        got=run.stdout.splitlines();want=[x[1] for x in batch]
        assert run.returncode==0 and not run.stderr and got==want,(label,start,run.returncode,run.stderr,next(((i,a,b) for i,(a,b) in enumerate(zip(got,want)) if a!=b),('length',len(got),len(want))))
    rows.append(dict(backend=label,cases=len(cases)));print(label,len(cases),'PASS',flush=True)
paths=['packages/runtime/src/dns-resolver.bend','packages/runtime/test/dns-address-answer.bend','tests/dns_address_answer_check.py','build/dns-address-answer','build/dns-address-answer.js']
(ROOT/'build/dns-address-answer-result.json').write_text(json.dumps({'scope':__doc__,'results':rows,'seed':1034,'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
