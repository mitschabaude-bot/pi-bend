"""VP8L codec: crafted grammar coverage and libwebp images against pinned Photon."""
import argparse
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
ORDER=[17,18,0,1,2,3,4,5,16,6,7,8,9,10,11,12,13,14,15]

class Bits:
    def __init__(self): self.bits=[]
    def put(self,value,count): self.bits.extend((value>>i)&1 for i in range(count))
    def code(self,value,count): self.bits.extend((value>>i)&1 for i in reversed(range(count)))
    def bytes(self): return bytes(sum(v<<j for j,v in enumerate(self.bits[i:i+8])) for i in range(0,len(self.bits),8))

def canonical(lengths):
    count=[lengths.count(i) for i in range(16)]; count[0]=0
    next_code=[0]*16
    for i in range(1,16): next_code[i]=(next_code[i-1]+count[i-1])<<1
    codes={}
    for symbol,n in enumerate(lengths):
        if n: codes[symbol]=(next_code[n],n);next_code[n]+=1
    if len(codes)==1: codes={next(iter(codes)):(0,0)}
    return codes

def tree(bits,symbols,alphabet,*,complex=False,repeats=True):
    symbols=sorted(set(symbols))
    if not complex and len(symbols)<=2 and max(symbols)<256:
        bits.put(1,1);bits.put(len(symbols)-1,1);bits.put(symbols[0]>1,1);bits.put(symbols[0],8 if symbols[0]>1 else 1)
        if len(symbols)==2:bits.put(symbols[1],8)
        return {s:(i,len(symbols)-1) for i,s in enumerate(symbols)}
    levels=[0]*alphabet
    if len(symbols)==1:levels[symbols[0]]=1
    else:
        low=len(symbols).bit_length()-1;short=(1<<(low+1))-len(symbols)
        for i,s in enumerate(symbols):levels[s]=low if i<short else low+1
    lengths=[4]*13+[5]*6;codes=canonical(lengths)
    bits.put(0,1);bits.put(15,4)
    for symbol in ORDER:bits.put(lengths[symbol],3)
    bits.put(0,1)
    i=0;previous=8
    while i<alphabet:
        n=levels[i];run=1
        while i+run<alphabet and levels[i+run]==n:run+=1
        if repeats and n==0 and run>=11:
            run=min(run,138);bits.code(*codes[18]);bits.put(run-11,7)
        elif repeats and n==0 and run>=3:
            run=min(run,10);bits.code(*codes[17]);bits.put(run-3,3)
        elif repeats and n==previous and n and run>=3:
            run=min(run,6);bits.code(*codes[16]);bits.put(run-3,2)
        else:
            run=1;bits.code(*codes[n]);previous=n or previous
        i+=run
    return canonical(levels)

def group(bits,color):
    for symbol in [(color>>8)&255,(color>>16)&255,color&255,color>>24,0]:tree(bits,[symbol],280)

def auxiliary(bits,color): bits.put(0,1);group(bits,color)
def payload(w,h,bits):return b'\x2f'+struct.pack('<I',(w-1)|((h-1)<<14))+bits.bytes()
def webp(data):
    chunk=b'VP8L'+struct.pack('<I',len(data))+data+b'\0'*(len(data)%2)
    return b'RIFF'+struct.pack('<I',len(chunk)+4)+b'WEBP'+chunk

def constant(w,h,color,transforms=()):
    b=Bits()
    for kind,param,value in transforms:
        b.put(1,1);b.put(kind,2)
        if kind in (0,1):b.put(param,3);auxiliary(b,value)
        if kind==3:b.put(param-1,8);auxiliary(b,value)
    b.put(0,1);b.put(0,1);b.put(0,1);group(b,color)
    return payload(w,h,b)

def prefix(value):
    if value<=4:return value-1,0,0
    extra=(value-1).bit_length()-2
    code=2*extra+2+(((value-1)>>extra)&1)
    return code,(value-1)&((1<<extra)-1),extra

def coded(w,h,tokens,cache=0,*,bits=None,auxiliary_stream=False):
    b=bits if bits is not None else Bits()
    if not auxiliary_stream:b.put(0,1)
    b.put(bool(cache),1)
    if cache:b.put(cache,4)
    if not auxiliary_stream:b.put(0,1)
    green=[];distance=[];red=[];blue=[];alpha=[]
    for kind,value,other in tokens:
        if kind=='literal':green.append((value>>8)&255);red.append((value>>16)&255);blue.append(value&255);alpha.append(value>>24)
        elif kind=='copy':green.append(256+prefix(value)[0]);distance.append(prefix(other)[0])
        else:green.append(280+value)
    sets=[green,red or [0],blue or [0],alpha or [0],distance or [0]]
    trees=[tree(b,s,280+(1<<cache) if cache and i==0 else 280 if i==0 else 40 if i==4 else 256,complex=True) for i,s in enumerate(sets)]
    for kind,value,other in tokens:
        if kind=='literal':
            for i,s in enumerate([(value>>8)&255,(value>>16)&255,value&255,value>>24]):b.code(*trees[i][s])
        elif kind=='copy':
            c,v,n=prefix(value);b.code(*trees[0][256+c]);b.put(v,n)
            c,v,n=prefix(other);b.code(*trees[4][c]);b.put(v,n)
        else:b.code(*trees[0][280+value])
    return payload(w,h,b)

def packed(argb):return ((argb<<8)&0xffffffff)|(argb>>24)
def expected(w,h,pixels,summary=False):
    if not summary:return f'{w}:{h}:'+','.join(map(str,pixels))
    digest=2166136261
    for value in pixels:digest=((digest*16777619)&0xffffffff)^value
    return f'{w}:{h}:hash:{digest}'

def fixtures():
    cases=[]
    def add(name,w,h,data,pixels=None):cases.append((name,w,h,data,pixels))
    for mode in range(14):
        for w,h in [(1,1),(1,9),(9,1),(9,7)]:add(f'predictor-{mode}-{w}-{h}',w,h,constant(w,h,0x00070b11,[(0,0,mode<<8)]))
    for a in [0,1,127,128,255]:
        for b in [0,1,127,128,255]:
            coefficients=(a<<16)|(b<<8)|a
            add(f'color-{a}-{b}',7,9,constant(7,9,0xaadce9f7,[(1,0,coefficients)]))
    for count in [1,2,3,4,5,16,17,127,256]:
        for w in [1,3,9]:add(f'palette-{count}-{w}',w,3,constant(w,3,0x0000e400,[(3,count,0x07110b03)]))
    for color in [0,0xffffffff,0x80fedcba,0xff00ff00]:
        add(f'subgreen-{color}',5,3,constant(5,3,color,[(2,0,0)]))
    rng=random.Random(289)
    for count in [1,2,3,4,5,17,128,256]:
        pixels=[rng.getrandbits(32) for _ in range(count)]
        add(f'literals-{count}',count,1,coded(count,1,[('literal',p,0) for p in pixels]),[packed(p) for p in pixels])
    for bits in range(1,12):
        color=0x8abcde17;index=((color*506832829)&0xffffffff)>>(32-bits)
        add(f'cache-{bits}',3,1,coded(3,1,[('literal',color,0),('cache',index,0),('cache',index,0)],bits),[packed(color)]*3)
    for length in [1,2,3,4,5,8,16,64,512,4096]:
        color=0xff394b17
        add(f'overlap-{length}',length+1,1,coded(length+1,1,[('literal',color,0),('copy',length,2)]),[packed(color)]*(length+1))
    # Every plane-distance code, then the linear-distance branch. History is
    # longer than every referenced distance; Photon supplies the independent map.
    history=[rng.getrandbits(32) for _ in range(220)]
    for distance in range(1,161):
        add(f'distance-{distance}',17,13,coded(17,13,[('literal',v,0) for v in history]+[('copy',1,distance)]))
    for selected in [0,1,7,255]:
        b=Bits();b.put(0,1);b.put(0,1);b.put(1,1);b.put(0,3)
        auxiliary(b,selected<<8)
        for index in range(selected+1):group(b,0xff000000|index)
        add(f'meta-{selected}',9,7,payload(9,7,b),[packed(0xff000000|selected)]*63)
    b=Bits();b.put(0,1);b.put(0,1);b.put(1,1);b.put(0,3)
    groups=[0,1,7,1,7,0]
    coded(3,2,[('literal',v<<8,0) for v in groups],bits=b,auxiliary_stream=True)
    for index in range(8):group(b,0xff070000|index)
    add('meta-spatial',9,7,payload(9,7,b),[packed(0xff070000|groups[(y//4)*3+x//4]) for y in range(7) for x in range(9)])
    for mode in range(14):
        add(f'combined-{mode}',9,7,constant(9,7,0x00121317,[(0,0,mode<<8),(1,0,0x007f81ff),(2,0,0)]))
    return cases

def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--photon',default=str(ROOT/'build/photon/photon_rs.js'));p.add_argument('--threads',default='1');p.add_argument('--skip-encoder',action='store_true');args=p.parse_args()
    runner=['bun',args.runner] if args.runner.endswith('.js') else [args.runner]
    env=dict(os.environ,BEND_THREADS=args.threads)
    cases=fixtures()
    if not args.skip_encoder:
        rng=random.Random(42)
        for n,(w,h,mode) in enumerate([(1,1,'solid'),(3,2,'solid'),(8,8,'palette'),(17,19,'gradient'),(32,31,'noise'),(64,64,'gradient'),(128,128,'noise'),(513,255,'gradient')]):
            data=bytes(v for y in range(h) for x in range(w) for v in ((10,20,30,255) if mode=='solid' else ((x+y)%4*64,x%4*60,y%4*70,255) if mode=='palette' else (x*255//w,y*255//h,(x+y)*255//(w+h),255) if mode=='gradient' else (rng.randrange(256),rng.randrange(256),rng.randrange(256),rng.randrange(1,256))))
            encoded=subprocess.run(['ffmpeg','-loglevel','error','-f','rawvideo','-pixel_format','rgba','-video_size',f'{w}x{h}','-i','pipe:0','-frames:v','1','-c:v','libwebp','-lossless','1','-compression_level','6','-threads','1','-f','webp','pipe:1'],input=data,capture_output=True,check=True).stdout
            pos=12
            while encoded[pos:pos+4]!=b'VP8L':pos+=8+int.from_bytes(encoded[pos+4:pos+8],'little')+(encoded[pos+4]&1)
            size=int.from_bytes(encoded[pos+4:pos+8],'little');raw=encoded[pos+8:pos+8+size]
            cases.append((f'libwebp-{n}',w,h,raw,[int.from_bytes(data[i:i+4],'big') for i in range(0,len(data),4)]))
    with tempfile.TemporaryDirectory() as tmp:
        paths=[];commands=[]
        for i,(_,w,h,data,pixels) in enumerate(cases):
            path=Path(tmp)/f'{i}.webp';path.write_bytes(webp(data));paths.append(str(path))
            if w*h>1000:
                rawpath=Path(tmp)/f'{i}.vp8l';rawpath.write_bytes(data);commands.append('!'+str(rawpath))
            else:commands.append(data.hex())
        references=subprocess.check_output(['bun',str(ROOT/'tests/png_reference.cjs'),str(Path(args.photon).resolve()),*paths],text=True).splitlines()
        actual=[]
        for start in range(0,len(commands),32):
            actual += subprocess.check_output([*runner,*commands[start:start+32]],text=True,env=env,timeout=180).splitlines()
        assert len(actual)==len(cases)==len(references)
        for (name,w,h,data,pixels),line,ref in zip(cases,actual,references):
            r=json.loads(ref);assert (r['width'],r['height'])==(w,h),name
            values=[int.from_bytes(bytes(r['rgba'][i:i+4]),'big') for i in range(0,len(r['rgba']),4)]
            if pixels is not None:assert values==pixels,('oracle mismatch',name)
            assert line==expected(w,h,values,w*h>1000),(name,line[:200],expected(w,h,values,w*h>1000)[:200])
    invalid=['invalid','', '00','2f00000020','@'+constant(2,2,0).hex()]
    invalid += [cases[-1][3][:n].hex() for n in range(min(24,len(cases[-1][3])))]
    # Invalid references are rejected before reading uninitialized history or
    # writing beyond the declared image; malformed transform/cache headers fail.
    invalid += [coded(1,1,[('copy',1,2)]).hex(),coded(2,1,[('literal',0xff000000,0),('copy',2,2)]).hex()]
    for cache in [0,12,13,14,15]:
        b=Bits();b.put(0,1);b.put(1,1);b.put(cache,4)
        invalid.append(payload(1,1,b).hex())
    invalid.append(constant(1,1,0,[(2,0,0),(2,0,0)]).hex())
    invalid.append(constant(2,2,0,[(0,0,14<<8)]).hex())
    results=subprocess.check_output([*runner,*invalid],text=True,env=env).splitlines()
    assert len(results)==len(invalid)
    assert all(r.startswith('error:') for r in results),results
    print(f'{len(cases)} exact Photon pixel checks; {len(invalid)} malformed/budget checks passed')

if __name__=='__main__':main()
