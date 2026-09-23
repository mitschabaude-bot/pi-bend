#!/usr/bin/env python3
"""Pinned Photon differential oracle; production encoder is entirely Bend."""
import argparse, base64, json, pathlib, random, subprocess, tempfile

p=argparse.ArgumentParser()
p.add_argument('--photon',default='build/photon/photon_rs.js')
p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args(); command=a.command
if command[:1]==['--']: command=command[1:]
if not command: p.error('provide encoder command after --')
rng=random.Random(94381)
cases=[]
for w,h in [(1,1),(1,9),(9,1),(7,9),(8,8),(9,9),(17,15)]:
    patterns=[[0xff]* (w*h),[0xffffffff]*(w*h),[0xff0000ff]*(w*h),[rng.getrandbits(32) for _ in range(w*h)], [((i*255//max(1,w*h-1))*0x01010100)|255 for i in range(w*h)]]
    for quality in [0,1,25,49,50,75,90,100,101,255]:
        for pixels in patterns: cases.append(dict(width=w,height=h,pixels=pixels,quality=quality))
for w,h,q in [(31,33,1),(32,32,75),(64,64,100)]:
    cases.append(dict(width=w,height=h,pixels=[rng.getrandbits(32) for _ in range(w*h)],quality=q))
state=17; generated=[]
for _ in range(256*256):
    state ^= (state<<13)&0xffffffff
    state ^= state>>17
    state ^= (state<<5)&0xffffffff
    generated.append(state)
cases.append(dict(width=256,height=256,pixels=generated,quality=90,seed=17))
# Alpha is discarded without changing RGB; exercise translucent saturated colors.
for alpha in [0,1,127,254,255]:
    cases.append(dict(width=3,height=2,pixels=[(rgb<<8)|alpha for rgb in [0xff0000,0x00ff00,0x0000ff,0xffffff,0,0xabcdef]],quality=90))

def argument(c,limit=1000000):
    if 'seed' in c: return f"random:{c['width']}:{c['height']}:{c['quality']}:{limit}:{c['seed']}"
    return f"pixels:{c['width']}:{c['height']}:{c['quality']}:{limit}:"+','.join(map(str,c['pixels']))

def run(args):
    result=subprocess.run(command+args,text=True,capture_output=True)
    assert result.returncode==0,(args[0][:60],result.stderr[-2000:])
    lines=result.stdout.splitlines()
    assert len(lines)==len(args),(len(lines),len(args),result.stderr)
    return lines

with tempfile.TemporaryDirectory(prefix='jpeg-reference-') as directory:
    paths=[]
    for i,c in enumerate(cases):
        path=pathlib.Path(directory)/f'{i}.json';path.write_text(json.dumps(c));paths.append(str(path))
    reference=[json.loads(s) for s in subprocess.check_output(['node','tests/jpeg_encode_reference.cjs',str(pathlib.Path(a.photon).resolve()),*paths],text=True).splitlines()]
    actual=[]
    for start in range(0,len(cases),20): actual.extend(run([argument(c) for c in cases[start:start+20]]))
    sizes=[]
    for i,(case,line,ref) in enumerate(zip(cases,actual,reference)):
        assert line.startswith('ok:'),(i,line)
        data=bytes(map(int,line[3:].split(','))); expected=base64.b64decode(ref['jpeg'])
        assert data==expected,(i,case['width'],case['height'],case['quality'],len(data),len(expected),next((j for j,(x,y) in enumerate(zip(data,expected)) if x!=y),None))
        assert ref['width']==case['width'] and ref['height']==case['height']
        sizes.append(len(data))
    assert len(set(actual[-5:]))==1,'alpha changed encoding'
    checks=[]; expected=[]
    for i in [0,33,107,222,349,354]:
        checks.extend([argument(cases[i],sizes[i]),argument(cases[i],sizes[i]-1),argument(cases[i],0)])
        expected.extend([actual[i],'error:limit','error:limit'])
    checks.extend(['invalid:0:1:75:10000','invalid:65536:1:75:10000','invalid:2:2:75:10000','invalid:1:1:256:10000'])
    expected.extend(['error:dimensions:0:1:16909060','error:dimensions:65536:1:16909060','error:pixels:2:2:16909060','error:quality:1:1:16909060'])
    assert run(checks)==expected,'budget, validation, or retained raster mismatch'
print(f'PASS {len(cases)} exact Photon JPEG encodings and {len(checks)} budget/validation cases; all raster pixels retained')
