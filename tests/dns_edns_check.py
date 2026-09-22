"""EDNS(0) query encoding against independent RFC 6891 byte construction."""
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-edns-{suffix}-build.json','--',str(bun),str(compiler),'tests/dns-edns.bend','-o',f'build/dns-edns.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-edns.c','-lpthread','-lm','-o','build/dns-edns'],cwd=ROOT,check=True)

def model(case):
    identifier,flags,payload,dnssec,kind,klass,mode,count,byte,code=case
    if max(identifier,flags,kind,klass)>65535:return ['message']
    if payload>65535:return ['field']
    if mode=='empty':options=[]
    elif mode=='many':options=[(code,0,0)]*count
    elif mode=='duplicate':options=[(0,0,0),(code,count,byte),(65535,2,0),(code,0,0)]
    else:options=[(code,count,byte)]
    data=b''
    for index,(tag,length,value) in enumerate(options):
        if tag>65535:return ['field']
        if length>65535:return ['long']
        if length and value>255:return [f'byte:{value}']
        if len(data)+length+4>65535:return ['long']
        chunk=bytes([value])*length if length else b''
        if mode=='duplicate' and index==2:chunk=b'\x00\xff'
        data+=struct.pack('!HH',tag,length)+chunk
    packet=struct.pack('!6H',identifier,flags,1,0,0,1)+b'\x01a\x00'+struct.pack('!HH',kind,klass)+b'\x00'+struct.pack('!HHIH',41,payload,32768 if dnssec else 0,len(data))+data
    if len(packet)>65535:return ['long']
    return [packet.hex(),'counts:1:1']

cases=[]
for identifier,flags,payload,dnssec in itertools.product([0,65535],[0,256,288,65535],[0,511,512,1232,4096,65535],[0,1]):
    cases.append((identifier,flags,payload,dnssec,1,1,'empty',0,0,0))
for mode,count,byte,code in itertools.product(['single','duplicate'],[0,1,4,255,256],[0,255],[0,10,65001,65535]):
    cases.append((42,256,1232,1,28,1,mode,count,byte,code))
for kind,klass in itertools.product([0,1,28,65535,65536],[0,1,65535,65536]):cases.append((1,256,1232,0,kind,klass,'empty',0,0,0))
for slot in [0,1,2]:
    case=[1,256,1232,0,1,1,'empty',0,0,0];case[slot]=65536;cases.append(tuple(case))
for mode in ['single','duplicate','many']:
    for code in [65536,4294967295]:cases.append((1,256,1232,0,1,1,mode,1,0,code))
for mode in ['single','duplicate']:
    for byte in [256,4294967295]:
        for count in [0,1,100]:cases.append((1,256,1232,0,1,1,mode,count,byte,1))
# Full-message and RDATA bounds are distinct. These use generated data so the
# OS argument-size limit never truncates the test input.
for count in [65486,65487,65488,65500,65501,65502,65531,65532,65535,65536]:
    for mode in ['single','duplicate']:cases.append((1,256,1232,0,1,1,mode,count,255,10))
for count in [0,1,16376,16377,16383,16384]:cases.append((1,256,1232,0,1,1,'many',count,0,65001))
checks=[]
for backend,command in [('native 1',['build/dns-edns','--threads','1']),('native 4',['build/dns-edns','--threads','4']),('Bun',[str(bun),'build/dns-edns.js'])]:
    for index,case in enumerate(cases):
        want=model(case)
        run=subprocess.run([*command,*map(str,case)],cwd=ROOT,capture_output=True,text=True,timeout=45)
        assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,case,run.returncode,run.stderr,run.stdout[:200],want[0][:200])
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} EDNS query cases PASS',flush=True)
paths=['packages/runtime/src/dns-message.bend','tests/dns-edns.bend','tests/dns_edns_check.py']
result=dict(scope=__doc__,reference='https://datatracker.ietf.org/doc/html/rfc6891',checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/dns-edns-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-edns-result.json').write_text(json.dumps(result,indent=2)+'\n')
