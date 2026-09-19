"""Immutable DNS pending-table transitions against an independent Python model.

Offline TCP dispatch contracts; no network, timer or transaction ID generator.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--no-build',action='store_true');args=p.parse_args()
if not args.no_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-pending-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/dns-pending.bend','build/dns-pending'],cwd=ROOT,check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/dns-pending-js-build.json','--',str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/dns-pending.bend','-o','build/dns-pending.js'],cwd=ROOT,check=True)

def wire(id,kind=1,flags=0x8180,qd=1,an=0):
    return list(struct.pack('!6H',id,flags,qd,an,0,0)+(b'\0'+struct.pack('!HH',kind,1) if qd else b''))

def receive(table,mode,data):
    if len(data)<2 or any(x>255 for x in data[:2]):return 'missing'
    id=data[0]*256+data[1]
    if id not in table:return f'unknown:{id}'
    if mode:return 'ignore:endpoint'
    if len(data)<12 or any(x>255 for x in data):return 'ignore:malformed'
    actual,flags,qd,an,ns,ar=struct.unpack('!6H',bytes(data[:12]))
    if not flags&0x8000:return 'ignore:query'
    if flags&0x7800:return 'ignore:opcode'
    if qd>1:return 'ignore:count'
    token,kind=table[id]
    if qd:
        if len(data)<17:return 'ignore:malformed'
        if data[12:17]!=[0,kind>>8,kind&255,0,1]:return 'ignore:question'
    if flags&512:
        del table[id];return f'truncated:{token}'
    if len(data)!=(17 if qd else 12) or an or ns or ar:return 'ignore:malformed'
    del table[id];return f'answer:{token}'

rng=random.Random(7766);sequences=[]
def scenario(operations):
    table={};saved={};commands=[];expected=[]
    for op in operations:
        if op[0]=='add':
            _,id,token,kind=op;commands.append(f'add:{id}:{token}:{kind}')
            if id>65535:expected.append('invalid')
            elif id in table:expected.append('duplicate')
            else:table[id]=(token,kind);expected.append('added')
        elif op[0]=='remove':
            _,id=op;commands.append(f'remove:{id}');old=table.pop(id,None);expected.append(f'removed:{old[0]}' if old else 'none')
        elif op[0]=='recv':
            _,mode,data=op;commands.append('recv:'+str(int(mode))+':'+','.join(map(str,data)));expected.append(receive(table,mode,data))
        elif op[0]=='save':commands.append('save');saved=table.copy();expected.append('saved')
        elif op[0]=='restore':commands.append('restore');table=saved.copy();expected.append('restored')
    # Drain every retained entry: catches collateral deletion or replacement.
    for id in list(table):commands.append(f'remove:{id}');expected.append(f'removed:{table[id][0]}')
    sequences.append((commands,expected))

for id in [0,1,255,256,32768,65535]:
    scenario([('add',id,41,1),('save',),('add',id,99,28),('recv',1,wire(id)),('recv',0,wire(id,28)),('recv',0,wire(id)),('recv',0,wire(id)),('restore',),('remove',id),('remove',id),('add',id,100,28),('recv',0,wire(id,28,qd=0))])
scenario([('add',id,id,1) for id in [65536,0xffffffff,0,65535]]+[('remove',id) for id in [65536,0xffffffff]]+[('recv',0,x) for x in [[],[0],[256,0],[0,0xffffffff],[0,0],[0,0]+[256]*10]])
# Simultaneously retain many IDs across every first-byte value, reverse replies.
ids=[high*256+low for high in range(256) for low in [0,1,255]]
scenario([('add',id,id+1,1) for id in ids]+[('save',)]+[('recv',0,wire(id)) for id in reversed(ids)]+[('restore',)])
for sequence in range(48):
    operations=[]
    for index in range(128):
        id=rng.choice([0,1,2,255,256,65535,sequence+100]);choice=rng.randrange(10)
        if choice<3:operations.append(('add',id,rng.randrange(0x100000000),rng.choice([1,28])))
        elif choice==3:operations.append(('remove',rng.choice([id,65536,0xffffffff])))
        elif choice==4:operations.append((rng.choice(['save','restore']),))
        else:
            data=wire(id,rng.choice([1,28]),rng.choice([0x8180,0x8380,0x8183,0x8980,0x0100]),rng.choice([0,1,1,2]),rng.choice([0,0,1]))
            mutation=rng.randrange(8)
            if mutation==0:data=data[:rng.randrange(len(data)+1)]
            elif mutation==1:data.append(0)
            elif mutation==2:data[rng.randrange(len(data))]=256
            operations.append(('recv',rng.randrange(8)==0,data))
    scenario(operations)
rows=[]
for label,command in [('native 1',['build/dns-pending','--threads','1']),('native 4',['build/dns-pending','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/dns-pending.js'])]:
    for index,(commands,expected) in enumerate(sequences):
        result=subprocess.run([*command,*commands],cwd=ROOT,capture_output=True,text=True,timeout=45)
        got=result.stdout.splitlines()
        assert result.returncode==0 and got==expected and not result.stderr,(label,index,result.returncode,result.stderr,next(((i,commands[i],a,b) for i,(a,b) in enumerate(zip(got,expected)) if a!=b),('length',len(got),len(expected))))
    rows.append(dict(backend=label,sequences=len(sequences),transitions=sum(len(x[0]) for x in sequences)))
    print(label,rows[-1],flush=True)
paths=['packages/runtime/src/dns-pending.bend','packages/runtime/test/dns-pending.bend','tests/dns_pending_check.py','build/dns-pending','build/dns-pending.js']
(ROOT/'build/dns-pending-result.json').write_text(json.dumps({'scope':__doc__,'results':rows,'seed':7766,'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}},indent=2)+'\n')
