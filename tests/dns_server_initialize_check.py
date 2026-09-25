"""Uniform random indices, byte decoding and owned DNS selector initialization."""
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUN=Path.home()/'.bun/bin/bun'
CANDIDATE=TOOLCHAIN
fixtures=['random-index','random-index-decode','dns-server-initialize']
for fixture in fixtures:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{fixture}-{suffix}-build.json','--',str(BUN),str(CANDIDATE/'main.ts'),f'tests/{fixture}.bend','-o',f'build/{fixture}.{suffix}'],cwd=ROOT,check=True)
    source=ROOT/f'build/{fixture}.c'
    if fixture=='dns-server-initialize':
        audited=ROOT/'build/dns-server-initialize-audit.c'
        audited.write_text(source.read_text()+'\nstatic void __attribute__((destructor)) audit(void) { unsigned live=0; for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live; fprintf(stderr,"LIVE %u\\n",live); }\n')
        source=audited
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1',str(source),'-lpthread','-lm','-o',f'build/{fixture}'],cwd=ROOT,check=True)

rng=random.Random(913)
width=1<<32
bounds=[0,1,2,3,5,7,15,16,17,255,256,257,65535,65536,65537,(1<<31)-1,1<<31,(1<<31)+1,width-2,width-1,width,width+1]
cases=[]
for bound in bounds:
    ceiling=width-width%bound if 0<bound<=width else 0
    words=sorted({0,1,2,127,255,65535,width-1,*[v for v in [ceiling-1,ceiling,ceiling+1] if 0<=v<width],*[rng.randrange(width) for _ in range(32)]})
    cases += [(bound,word) for word in words]
cases += [(rng.randrange(1,width),rng.randrange(width)) for _ in range(2048)]

def bound_arg(n):return 'full' if n==width else 'large' if n==width+1 else str(n)
def expected(bound,word):
    if not 0<bound<=width:return 'invalid'
    ceiling=width-width%bound
    return str(word%bound) if word<ceiling else 'reject'

decode=[([], 'bytes'),([0]*3,'bytes'),([0]*5,'bytes'),([0]*4,'0'),([255]*4,str(width-1))]
for i in range(4):
    for invalid in [256,65535,width-1]:
        values=[0]*4;values[i]=invalid;decode.append((values,'bytes'))
for _ in range(128):
    values=[rng.randrange(256) for _ in range(4)];decode.append((values,str(int.from_bytes(bytes(values),'big'))))

scripted=[([],['error'],0,0,None),([7],['error'],0,0,None),([0,1], [width-1],1,1,None),([0,1,2],[0],0,1,None),([0,1,2],[1],1,1,None),([0,1,2],[width-2],(width-2)%3,1,None),([0,1,2],[width-1,2],2,2,None),([9,9,7],[2],2,1,None),([0,1,2],['error'],0,1,'error:11:unavailable'),([0,1,2],[width-1,'error'],0,2,'error:11:unavailable'),([0,1,2],[width-1],0,2,'error:99:exhausted'),([0,1,2],[width-1]*10002+[1],1,10003,None)]
def csv(values):return ''.join(str(v)+',' for v in values)
def orders(values,offset):
    at=offset%len(values) if values else 0
    current=values[at:]+values[:at];out=[csv(values)]
    for _ in range(4):
        out.append(csv(current))
        if current:current=current[1:]+current[:1]
    return out

def invoke(backend,fixture,args):
    command=[str(BUN),f'build/{fixture}.js'] if backend=='Bun' else [f'build/{fixture}','--threads',backend.split()[-1]]
    run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
    want_error='LIVE 0\n' if fixture=='dns-server-initialize' and backend!='Bun' else ''
    assert run.returncode==0 and run.stderr==want_error,(backend,fixture,run.returncode,run.stderr)
    return run.stdout.splitlines()

checks=[]
for backend in ['native 1','native 4','Bun']:
    for start in range(0,len(cases),128):
        batch=cases[start:start+128]
        args=[text for bound,word in batch for text in [bound_arg(bound),str(word)]]
        assert invoke(backend,'random-index',args)==[expected(*case) for case in batch],(backend,start)
    args=[','.join(map(str,values)) for values,_ in decode]+['error']
    assert invoke(backend,'random-index-decode',args)==[out for _,out in decode]+['error:11:unavailable'],backend
    for values,words,offset,draws,error in scripted:
        actual=invoke(backend,'dns-server-initialize',['script',','.join(map(str,values)),','.join(map(str,words))])
        want=([error] if error else orders(values,offset))+['draws:'+str(draws)]
        assert actual==want,(backend,values,offset,draws,actual,want)
    for bound,words,want in [('0','error',['bound','draws:0']),('large','error',['bound','draws:0']),('1','error',['0','draws:0']),('full',str(width-1),[str(width-1),'draws:1']),('3',str(width-1)+',2',['2','draws:2'])]:
        assert invoke(backend,'dns-server-initialize',['index',bound,words])==want,(backend,bound)
    for _ in range(20):
        actual=invoke(backend,'dns-server-initialize',['os','0,1,2',''])
        assert actual in [orders([0,1,2],offset)+['draws:0'] for offset in range(3)],(backend,actual)
    checks.append(dict(backend=backend,index_cases=len(cases),decode_cases=len(decode)+1,scripted_initializations=len(scripted),direct_sampler_checks=5,os_initializations=20,native_live_channels=0 if backend!='Bun' else None))
    print(backend+': random index and selector initialization PASS',flush=True)
paths=['packages/runtime/src/random.bend','packages/runtime/src/dns-transport.bend', 'packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns_server_initialize_check.py']+[f'tests/{f}.bend' for f in fixtures]
r=dict(scope=__doc__,checks=checks,scripted=scripted[:-1],long_rejection_case=dict(rejections=10002,accepted_word=1,draws=10003),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},case_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),builds={f'{f}-{s}':json.loads((ROOT/f'build/{f}-{s}-build.json').read_text()) for f in fixtures for s in ['c','js']},compiler_sha256={p:hashlib.sha256((CANDIDATE/p).read_bytes()).hexdigest() for p in ['main.ts','comp.ts','bend.ts','base.bend']})
(ROOT/'build/dns-server-initialize-result.json').write_text(json.dumps(r,indent=2)+'\n')
