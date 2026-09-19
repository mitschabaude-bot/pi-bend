"""Bounded CRLF framing across chunk partitions; no text decoding or HTTP policy."""
import itertools
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
for n in range(5):
    for seq in itertools.product([10,13,65,255],repeat=n):
        for mask in range(1 << max(0,n-1)):
            chunks=[];start=0
            for i in range(1,n):
                if mask & (1 << (i-1)):
                    chunks.append(list(seq[start:i]));start=i
            chunks.append(list(seq[start:]))
            for limit in [0,1,4]:cases.append((limit,chunks))
rng=random.Random(98111)
for _ in range(600):
    payload=[rng.randrange(256) for _ in range(rng.randrange(64))]
    seq=payload+[13,10]+[0,255,13,10,256]
    cuts=sorted({0,len(seq),*(rng.randrange(len(seq)+1) for _ in range(8))})
    chunks=[seq[a:b] for a,b in zip(cuts,cuts[1:])]
    chunks.insert(rng.randrange(len(chunks)+1),[])
    cases.append((rng.choice([len(payload),len(payload)+1,max(0,len(payload)-1)]),chunks))
for bad in [256,65535,4294967295]:
    for limit in [0,1,4]:
        for chunks in [[[bad]],[[13],[bad]],[[65,bad]],[[13,10,bad]],[[65,13,10],[bad]]]:cases.append((limit,chunks))
cases += [(0,[[],[],[13],[],[10,99]]),(1,[[65,13],[10,99]]),(1,[[13],[13],[10]]),(1,[[13],[65]])]

def codes(values):return ','.join(map(str,values))
def expected(limit,chunks):
    buffered=[];trace=[]
    for chunk in chunks:
        trace.append('more')
        for index,value in enumerate(chunk):
            if value>255:return '|'.join(trace+['invalid:'+str(value)])
            buffered.append(value)
            # Examine the whole prefix independently of the implementation's
            # pending-CR representation. Only an actual CRLF completes a line.
            if len(buffered)>=2 and buffered[-2:]==[13,10]:
                return '|'.join(trace+['line:'+codes(buffered[:-2])+';'+codes(chunk[index+1:])])
            payload=len(buffered)-(1 if buffered[-1]==13 else 0)
            if payload>limit:return '|'.join(trace+['long'])
    return '|'.join(trace+['incomplete'])
args=[str(limit)+''.join(';'+codes(chunk) for chunk in chunks) for limit,chunks in cases]
want=[expected(limit,chunks) for limit,chunks in cases]
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-line.bend','build/http-line'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/http-line'),'--threads',threads,*args[start:start+64]],cwd=ROOT,capture_output=True,text=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+64],(threads,start,p.stdout,want[start:start+64])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'bounded CRLF partition cases PASS')
