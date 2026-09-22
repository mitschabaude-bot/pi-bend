#!/usr/bin/env python3
"""External zlib roundtrips, deterministic encoding, LZ77 boundaries and budgets."""
import argparse
import random
import subprocess
import zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',default='build/deflate-encode');a=p.parse_args()
rng=random.Random(1953)
fixtures=[]
for n in [0,1,2,3,4,5,10,11,18,34,66,130,257,258,259,1024,16384]:
    for data in [b'a'*n,(b'abcde'*((n+4)//5))[:n],rng.randbytes(n)]:
        fixtures.append(('bytes',data,None))
for distance in [3,4,5,8,9,16,17,32,33,128,129,256,257,1024,16384,32767,32768]:
    data=rng.randbytes(distance)
    fixtures.append(('bytes',data+data[:258],None))
for n in [32768,32769,65535,65536,70000]:
    state=12345;data=bytearray()
    for _ in range(n):
        state^=(state<<13)&0xffffffff;state^=state>>17;state^=(state<<5)&0xffffffff;data.append(state&255)
    fixtures.append(('random',bytes(data),12345))
fixtures.append(('repeat',b'abcde'*20000,b'abcde'))


def request(fixture,mode,limit):
    kind,data,extra=fixture
    if kind=='random':return f'random:{mode}:{len(data)}:{limit}:{extra}'
    if kind=='repeat':return f'repeat:{mode}:{len(data)//len(extra)}:{limit}:'+','.join(map(str,extra))
    return f'{mode}:{limit}:'+','.join(map(str,data))

reference={}
for backend in a.backends:
    command=['bun',str(ROOT/(a.prefix+'.js'))] if backend=='bun' else [str(ROOT/a.prefix),'--threads',backend.split('-')[1]]
    count=0
    for mode in ['raw','zlib']:
        for i,fixture in enumerate(fixtures):
            data=fixture[1]
            run=subprocess.run(command+[request(fixture,mode,len(data)*2+100)],capture_output=True,text=True,timeout=60)
            assert run.returncode==0,(backend,i,run.stderr)
            assert run.stdout.startswith('ok '),(backend,i,run.stdout[:100])
            encoded=bytes(map(int,run.stdout[3:].strip().split(',')))
            assert zlib.decompress(encoded,-15 if mode=='raw' else 15)==data,(backend,i)
            key=(mode,i)
            if key in reference:assert reference[key]==encoded,(backend,'nondeterministic',i)
            reference[key]=encoded
            # The chosen representation is never larger than stored blocks.
            assert len(encoded)<=len(data)+5*max(1,(len(data)+65534)//65535)+(6 if mode=='zlib' else 0)
            if len(data)>=1000 and len(set(data))<=5:assert len(encoded)<len(data)//10
            exact=subprocess.run(command+[request(fixture,mode,len(encoded)),request(fixture,mode,len(encoded)-1)],capture_output=True,text=True,timeout=60)
            assert exact.returncode==0,exact.stderr
            assert exact.stdout.splitlines()==['ok '+','.join(map(str,encoded)),'error limit'],(backend,i,exact.stdout[:100])
            count+=3
        check=subprocess.run(command+[f'{mode}:100:256',f'{mode}:0:',f'{mode}:1:'],capture_output=True,text=True)
        assert check.stdout.splitlines()==['error byte','error limit','error limit'],check.stdout
        count+=3
    print(f'{backend}: {count} compression roundtrip/budget/determinism checks pass',flush=True)
