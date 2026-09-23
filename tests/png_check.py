#!/usr/bin/env python3
"""PNG fixtures generated independently, checked against pinned Photon and Bend."""
import argparse
import base64
import hashlib
import io
import json
import random
import struct
import subprocess
import tarfile
import tempfile
import urllib.request
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('backends', nargs='*', default=['bun','native-1','native-4'])
parser.add_argument('--prefix', default='build/png')
parser.add_argument('--photon', default='build/photon/photon_rs.js')
parser.add_argument('--fetch-oracle', action='store_true')
args = parser.parse_args()
photon = (ROOT / args.photon).resolve()
if args.fetch_oracle:
    payload = urllib.request.urlopen('https://registry.npmjs.org/@silvia-odwyer/photon-node/-/photon-node-0.3.4.tgz').read()
    expected = 'bnly4BKB3KDTFxrUIcgCLbaeVVS8lrAkri1pEzskpmxu9MdfGQTy8b8EgcD83ywD3RPMsIulY8xJH5Awa+t9fA=='
    assert base64.b64encode(hashlib.sha512(payload).digest()).decode() == expected
    photon.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as archive:
        for name in ['photon_rs.js','photon_rs_bg.wasm','package.json']:
            (photon.parent/name).write_bytes(archive.extractfile('package/'+name).read())
assert photon.exists(), 'Run with --fetch-oracle to obtain pinned test-only Photon 0.3.4'
assert json.loads((photon.parent/'package.json').read_text())['version'] == '0.3.4'

SIGNATURE = b'\x89PNG\r\n\x1a\n'
PASSES = [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
DEPTHS = {0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]}
CHANNELS = {0:1,2:3,3:1,4:2,6:4}
rng = random.Random(1952)
cases = []
valid = []


def chunk(kind, data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))


def ihdr(w,h,depth,color,interlace=0):
    return chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,depth,color,0,0,interlace))


def paeth(a,b,c):
    p=a+b-c
    return min([(abs(p-a),0,a),(abs(p-b),1,b),(abs(p-c),2,c)])[2]


def serialize(samples, depth):
    if depth == 16:
        return struct.pack('>'+'H'*len(samples),*samples)
    if depth == 8:
        return bytes(samples)
    bits = ''.join(f'{x:0{depth}b}' for x in samples)
    bits += '0' * (-len(bits)%8)
    return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))


def scanlines(w,h,color,depth,pixels,interlace,filter):
    output=bytearray()
    for x,y,dx,dy in PASSES if interlace else [(0,0,1,1)]:
        if x>=w or y>=h:
            continue
        previous=None
        for row in range(y,h,dy):
            raw=serialize([s for col in range(x,w,dx) for s in pixels[row*w+col]],depth)
            bpp=max(1,(CHANNELS[color]*depth+7)//8)
            filtered=bytearray()
            for i,value in enumerate(raw):
                a=raw[i-bpp] if i>=bpp else 0
                b=previous[i] if previous else 0
                c=previous[i-bpp] if previous and i>=bpp else 0
                prediction=[0,a,b,(a+b)//2,paeth(a,b,c)][filter]
                filtered.append((value-prediction)%256)
            output.extend(bytes([filter])+filtered)
            previous=raw
    return bytes(output)


def add(label, data, expected, limit=None, dimensions=None):
    if isinstance(expected,list):
        w,h=dimensions
        result=f'ok {w},{h}'+''.join(','+str(x) for x in expected)
        limit=w*h if limit is None else limit
        valid.append((label,data,w,h,expected))
    else:
        result='error '+expected
        limit=1000000 if limit is None else limit
    cases.append((label,str(limit)+':'+','.join(map(str,data)),result))


def image(w,h,color,depth,interlace,filter,transparent=False,split=False,ancillary=False):
    maximum=(1<<depth)-1
    count=min(1<<depth,13) if color==3 else 0
    palette=[tuple(rng.randrange(256) for _ in range(3)) for _ in range(count)]
    alpha=[0,128,255,1][:count] if transparent else []
    pixels=[tuple(rng.randrange(count if color==3 else maximum+1) for _ in range(CHANNELS[color])) for _ in range(w*h)]
    key=pixels[0] if color in [0,2] and transparent else None
    rgba=[]
    scale=lambda x: (x+128)//257 if depth==16 else x*255//maximum
    for pixel in pixels:
        if color==3:
            i=pixel[0]
            sample=(*palette[i],alpha[i] if i<len(alpha) else 255)
        elif color==0:
            sample=(scale(pixel[0]),)*3+(0 if pixel==key else 255,)
        elif color==2:
            sample=tuple(map(scale,pixel))+(0 if pixel==key else 255,)
        elif color==4:
            sample=(scale(pixel[0]),)*3+(scale(pixel[1]),)
        else:
            sample=tuple(map(scale,pixel))
        rgba.append(int.from_bytes(bytes(sample),'big'))
    out=SIGNATURE+ihdr(w,h,depth,color,interlace)
    if palette:
        out+=chunk(b'PLTE',bytes(x for rgb in palette for x in rgb))
    if key is not None:
        out+=chunk(b'tRNS',struct.pack('>'+'H'*len(key),*key))
    if alpha:
        out+=chunk(b'tRNS',bytes(alpha))
    if ancillary:
        out+=chunk(b'gAMA',struct.pack('>I',45455))+chunk(b'tEXt',b'Name\0unchanged raw samples')
    packed=zlib.compress(scanlines(w,h,color,depth,pixels,interlace,filter))
    fragments=[packed[:1],b'',packed[1:3],packed[3:-1],packed[-1:]] if split else [packed]
    out+=b''.join(chunk(b'IDAT',p) for p in fragments)+chunk(b'IEND',b'')
    return out,rgba


for color,depths in DEPTHS.items():
    for depth in depths:
        for interlace in [0,1]:
            for filter in range(5):
                data,pixels=image(9,11,color,depth,interlace,filter,True,True,True)
                add(f'color {color} depth {depth} interlace {interlace} filter {filter}',data,pixels,dimensions=(9,11))
                if filter==0:
                    add('pixel budget below image',data,'limit',98)
        for w,h in [(1,1),(1,7),(7,1),(2,2),(3,5)]:
            data,pixels=image(w,h,color,depth,1,4)
            add('Adam7 small or empty passes',data,pixels,dimensions=(w,h))
# Exact 16-bit scaling/alpha boundaries, including equal high bytes but distinct tRNS samples.
for color in [0,2,4,6]:
    values=[0,128,129,255,256,257,32767,32768,65407,65408,65535]
    pixels=[(v,)*CHANNELS[color] for v in values]
    raw=scanlines(len(values),1,color,16,pixels,0,0)
    data=SIGNATURE+ihdr(len(values),1,16,color)
    if color in [0,2]: data+=chunk(b'tRNS',struct.pack('>'+'H'*CHANNELS[color],*([128]*CHANNELS[color])))
    data+=chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
    output=[]
    for v in values:
        s=(v+128)//257
        alpha=s if color in [4,6] else 0 if v==128 else 255
        output.append(int.from_bytes(bytes([s,s,s,alpha]),'big'))
    add('16-bit rescale/transparency boundaries',data,output,dimensions=(len(values),1))
# APNG default image is the image consumed by Photon; later frame data is ancillary here.
data,pixels=image(3,2,6,8,0,0)
fc=struct.pack('>IIIIIHHBB',0,3,2,0,0,1,10,0,0)
data=data[:33]+chunk(b'acTL',struct.pack('>II',1,0))+chunk(b'fcTL',fc)+data[33:]
add('APNG default frame',data,pixels,dimensions=(3,2))

# Default image excluded from animation: later fdAT pixels must not replace it.
data,pixels=image(3,2,6,8,0,0)
fc=struct.pack('>IIIIIHHBB',0,2,2,0,0,1,10,0,0)
frame=zlib.compress(bytes([0])+bytes(8)+bytes([0])+bytes(8))
data=data[:33]+chunk(b'acTL',struct.pack('>II',1,0))+data[33:-12]+chunk(b'fcTL',fc)+chunk(b'fdAT',struct.pack('>I',1)+frame)+data[-12:]
add('APNG separate default image',data,pixels,dimensions=(3,2))
# A long scanline and many pixels exercise list traversal beyond JS stack depth.
w,h=32769,2
pixels=[(i%16,(i//16)%16,(i//256)%16,255) for i in range(w*h)]
raw=scanlines(w,h,6,8,pixels,0,4)
data=SIGNATURE+ihdr(w,h,8,6)+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
add('long scanline and 65538 pixels',data,[int.from_bytes(bytes(p),'big') for p in pixels],dimensions=(w,h))

base,basepixels=image(3,2,6,8,0,0)
header=SIGNATURE+ihdr(1,1,8,6)
ending=chunk(b'IEND',b'')
packed=chunk(b'IDAT',zlib.compress(b'\0\1\2\3\4'))
for label,data,error in [
    ('empty',b'','signature'),('wrong signature',b'not PNG!','signature'),
    ('invalid byte',[300],'byte'),('truncated chunk',SIGNATURE+b'\0','truncated'),
    ('oversized length',SIGNATURE+b'\x80\0\0\0IHDR','length'),
    ('bad chunk letters',header+chunk(b'a1CD',b''),'type'),
    ('reserved type bit',header+chunk(b'abcd',b''),'type'),
    ('unknown critical',header+chunk(b'ABCD',b''),'critical'),
    ('bad CRC',base[:-1]+bytes([base[-1]^1]),'crc'),
    ('duplicate header',header+ihdr(1,1,8,6)+packed+ending,'order'),
    ('missing header',SIGNATURE+packed+ending,'order'),
    ('missing IDAT',header+ending,'order'),
    ('missing IEND',header+packed,'truncated'),
    ('nonempty IEND',header+packed+chunk(b'IEND',b'x'),'order'),
    ('trailing data',base+b'x','order'),
    ('separated IDAT',header+packed+chunk(b'tEXt',b'A\0B')+chunk(b'IDAT',b'')+ending,'order'),
    ('forbidden transparency',header+chunk(b'tRNS',b'\0')+packed+ending,'transparency'),
    ('invalid filter',header+chunk(b'IDAT',zlib.compress(b'\5\1\2\3\4'))+ending,'filter'),
    ('short scanline',header+chunk(b'IDAT',zlib.compress(b'\0\1\2\3'))+ending,'scanline'),
    ('extra scanline byte',header+chunk(b'IDAT',zlib.compress(b'\0\1\2\3\4\5'))+ending,'compressed'),
    ('bad zlib',header+chunk(b'IDAT',b'broken')+ending,'compressed'),
    ('palette missing',SIGNATURE+ihdr(1,1,1,3)+packed+ending,'order'),
    ('palette malformed',SIGNATURE+ihdr(1,1,1,3)+chunk(b'PLTE',b'\1\2'),'palette'),
    ('palette too many',SIGNATURE+ihdr(1,1,1,3)+chunk(b'PLTE',bytes(9)),'palette'),
    ('palette forbidden',SIGNATURE+ihdr(1,1,8,0)+chunk(b'PLTE',bytes(3)),'palette'),
    ('palette index invalid',SIGNATURE+ihdr(1,1,8,3)+chunk(b'PLTE',bytes(3))+chunk(b'IDAT',zlib.compress(b'\0\1'))+ending,'index'),
    ('transparency before palette',SIGNATURE+ihdr(1,1,1,3)+chunk(b'tRNS',b'\0'),'transparency'),
    ('optional palette after transparency',SIGNATURE+ihdr(1,1,8,2)+chunk(b'tRNS',bytes(6))+chunk(b'PLTE',bytes(3)),'order'),
    ('duplicate transparency',SIGNATURE+ihdr(1,1,8,0)+chunk(b'tRNS',bytes(2))+chunk(b'tRNS',bytes(2)),'order'),
    ('duplicate palette',SIGNATURE+ihdr(1,1,8,3)+chunk(b'PLTE',bytes(3))+chunk(b'PLTE',bytes(3)),'order'),
    ('oversized alpha palette',SIGNATURE+ihdr(1,1,8,3)+chunk(b'PLTE',bytes(3))+chunk(b'tRNS',bytes(2)),'transparency'),
]: add(label,data,error)
for w,h in [(0,1),(1,0),(0x80000000,1),(1,0xffffffff),(0xffffffff,0xffffffff)]:
    add('invalid dimensions',SIGNATURE+ihdr(w,h,8,6),'header')
add('oversized dimension product',SIGNATURE+ihdr(0x7fffffff,0x7fffffff,8,6),'limit')
for color,depth in [(1,8),(5,8),(7,8),(2,4),(3,16),(4,1),(6,2),(0,3)]:
    add('invalid color/depth',SIGNATURE+ihdr(1,1,depth,color),'header')
for depth in [1,2,4,8]:
    add('out-of-range grayscale transparency',SIGNATURE+ihdr(1,1,depth,0)+chunk(b'tRNS',struct.pack('>H',1<<depth)),'transparency')
for channel in range(3):
    key=[0,0,0]; key[channel]=256
    add('out-of-range truecolor transparency',SIGNATURE+ihdr(1,1,8,2)+chunk(b'tRNS',struct.pack('>HHH',*key)),'transparency')
add('empty indexed transparency',SIGNATURE+ihdr(1,1,8,3)+chunk(b'PLTE',bytes(3))+chunk(b'tRNS',b''),'transparency')
for cut in range(8,len(base)):
    # Cuts within complete framing always leave the next chunk incomplete.
    add('truncated framing',base[:cut],'truncated')

with tempfile.TemporaryDirectory(prefix='png-oracle-') as directory:
    files=[]
    for i,(_,data,_,_,_) in enumerate(valid):
        file=Path(directory)/f'{i}.png'; file.write_bytes(data); files.append(str(file))
    for start in range(0,len(valid),32):
        result=subprocess.run(['bun',str(ROOT/'tests/png_reference.cjs'),str(photon),*files[start:start+32]],capture_output=True,text=True,timeout=60)
        assert result.returncode==0,result.stderr
        records=[json.loads(line) for line in result.stdout.splitlines()]
        assert len(records)==len(valid[start:start+32])
        for got,(label,_,w,h,expected) in zip(records,valid[start:start+32]):
            rgba=got['rgba']; actual=[int.from_bytes(bytes(rgba[i:i+4]),'big') for i in range(0,len(rgba),4)]
            assert (got['width'],got['height'],actual)==(w,h,expected),(label,actual[:20],expected[:20])
print(f'Photon 0.3.4: {len(valid)} generated images match independent pixels',flush=True)
for backend in args.backends:
    command=['bun',str(ROOT/(args.prefix+'.js'))] if backend=='bun' else [str(ROOT/args.prefix),'--threads',backend.split('-')[1]]
    for start in range(0,len(cases),16):
        batch=cases[start:start+16]
        result=subprocess.run(command+[x[1] for x in batch],capture_output=True,text=True,timeout=60)
        assert result.returncode==0,(backend,result.returncode,result.stderr)
        lines=result.stdout.splitlines(); assert len(lines)==len(batch),(backend,len(lines),len(batch))
        for actual,(label,_,expected) in zip(lines,batch):
            assert actual==expected,(backend,label,actual[:200],expected[:200])
    print(f'{backend}: {len(cases)} PNG cases pass',flush=True)
