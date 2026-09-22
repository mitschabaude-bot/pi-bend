"""Streaming accumulator snapshots and actual spill bytes against pinned Pi."""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
UPSTREAM=ROOT.parent/'pi-mono/packages/coding-agent/src/core/tools/output-accumulator.ts'

def parsed(line):
    fields=line.split('|');assert len(fields)==14,fields
    status,content,truncated,cause,lines,size,outlines,outsize,partial,first,maxlines,maxbytes,last,path=fields
    return {'status':status,'truncation':{'content':''.join(chr(int(c)) for c in content.split(',') if c),'truncated':truncated=='1','truncatedBy':None if cause=='none' else cause,'totalLines':int(lines),'totalBytes':int(size),'outputLines':int(outlines),'outputBytes':int(outsize),'lastLinePartial':partial=='1','firstLineExceedsLimit':first=='1','maxLines':int(maxlines),'maxBytes':int(maxbytes)},'last':int(last),'path':bool(path)},path

def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');args=p.parse_args()
    runner=['bun',args.runner] if args.runner.endswith('.js') else [args.runner,'--threads',args.threads]
    cases=[]
    def add(chunks,lines,size):cases.append({'lines':lines,'bytes':size,'commands':[v.hex() for v in chunks]+['s','f','f','s','c','c']})
    for raw in [b'',b'a',b'\n',b'\n\n',b'a\nb\n',b'\r\nx','é漢😀\nnext\n'.encode(),b'\xef\xbb\xbfhello',b'\xef\xbb\xbf\xef\xbb\xbf',b'\xff\xfe\x80',b'\xf0\x9f',b'a\0b']:
        for lines in [0,1,3]:
            for size in [0,1,4,12]:
                add([raw],lines,size)
                add([raw[i:i+1] for i in range(len(raw))],lines,size)
    rng=random.Random(374)
    for _ in range(90):
        raw=bytes(rng.randrange(256) for _ in range(rng.randrange(150))) if rng.randrange(3)==0 else ''.join(rng.choice('abc\n\r\t漢😀é\ufeff') for _ in range(rng.randrange(150))).encode()
        chunks=[];i=0
        while i<len(raw):n=rng.randrange(1,12);chunks.append(raw[i:i+n]);i+=n
        add(chunks,rng.randrange(12),rng.randrange(40))
    add([b'\xf0\x9f'],3,2)
    add([b'\xef\xbb\xbf'],3,2)
    add([b'x'*200000+b'\nlast\n'],3,64)
    add([b'line\n']*2500,2000,51200)
    add([b'\xf0',b'\x9f',b'\x98',b'\x80'],None,None)
    env=dict(os.environ,BEND_THREADS=args.threads)
    with tempfile.TemporaryDirectory() as tmp:
        casefile=Path(tmp)/'cases.json';casefile.write_text(json.dumps(cases));env['TMPDIR']=tmp
        refs=[json.loads(x) for x in subprocess.check_output(['bun',str(ROOT/'tests/output_accumulator_reference.ts'),str(UPSTREAM),str(casefile)],text=True,env=env).splitlines()]
        # The large single chunk uses a fixture-generated payload to stay below
        # Linux's per-argument limit; it is supplied as a named fixture token.
        commands=[]
        for item in cases:
            parts=item['commands'].copy()
            parts=['L' if len(c)>300000 else c for c in parts]
            commands.append(f"{'' if item['lines'] is None else item['lines']}:{'' if item['bytes'] is None else item['bytes']}:"+';'.join(parts))
        results=[]
        for start in range(0,len(commands),24):
            output=subprocess.check_output([*runner,*commands[start:start+24]],text=True,env=env,timeout=180)
            groups=output.split('end\n');assert groups[-1]==''
            for group in groups[:-1]:
                snapshots=[];lastpath=''
                for line in group.splitlines():
                    snap,path=parsed(line);snapshots.append(snap)
                    if path:lastpath=path
                raw=Path(lastpath).read_bytes().hex() if lastpath else None
                if lastpath:
                    assert Path(lastpath).stat().st_mode&0o777==0o600
                    Path(lastpath).unlink()
                results.append({'snapshots':snapshots,'raw':raw})
        assert len(results)==len(refs)
        for i,(actual,wanted) in enumerate(zip(results,refs)):
            assert actual==wanted,(i,cases[i],actual,wanted)
    print(f'{len(cases)} pinned streaming cases; {sum(len(c["commands"])+1 for c in cases)} snapshots; raw spill bytes and0600 permissions passed')

if __name__=='__main__':main()
