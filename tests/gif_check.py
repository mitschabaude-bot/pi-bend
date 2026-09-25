"""Native first-frame GIF against generated pixels and pinned Photon 0.3.4."""
import argparse
import json
import math
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
RNG=random.Random(817)
WIDTHS=set()
SPECIALS=0
FULL_RESETS=0


def codes(values,minimum,interval=0):
    clear=1<<minimum
    output=[]
    for start in range(0,len(values),interval or len(values)):
        table={(i,):i for i in range(clear)};next_code=clear+2
        output.append(clear);word=()
        for value in values[start:start+(interval or len(values))]:
            longer=word+(value,)
            if longer in table:word=longer
            else:
                output.append(table[word])
                if next_code<4096:table[longer]=next_code;next_code+=1
                word=(value,)
        if word:output.append(table[word])
    return output+[clear+1]


def packed(codes,minimum):
    global SPECIALS,FULL_RESETS
    clear=1<<minimum;next_code=clear+2;width=minimum+1;previous=False;word=0;bits=0;output=bytearray()
    for code in codes:
        WIDTHS.add(width)
        word|=code<<bits;bits+=width
        while bits>=8:output.append(word&255);word>>=8;bits-=8
        if code==clear:
            FULL_RESETS += int(next_code==4096)
            next_code=clear+2;width=minimum+1;previous=False
        elif code!=clear+1:
            SPECIALS += int(previous and code==next_code)
            if previous and next_code<4096:
                next_code+=1
                if next_code==1<<width and width<12:width+=1
            previous=True
    if bits:output.append(word)
    return bytes(output)


def blocks(data,split=255):
    return b''.join(bytes([len(data[i:i+split])])+data[i:i+split] for i in range(0,len(data),split))+b'\0'


def frame(w,h,values,*,left=0,top=0,palette=None,minimum=2,interlace=False,split=255,interval=0,override=None):
    ordered=[values[y*w+x] for start,step in ([(0,8),(4,8),(2,4),(1,2)] if interlace else [(0,1)]) for y in range(start,h,step) for x in range(w)]
    compressed=packed(codes(ordered,minimum,interval),minimum) if override is None else override
    flags=(64 if interlace else 0)|(128+int(math.log2(len(palette)))-1 if palette else 0)
    return b','+struct.pack('<HHHHB',left,top,w,h,flags)+(bytes(sum((list(x) for x in palette),[])) if palette else b'')+bytes([minimum])+blocks(compressed,split)


def gif(sw,sh,w,h,values,*,palette,local=False,no_global=False,left=0,top=0,transparent=None,interlace=False,split=255,interval=0,extensions=b'',version=b'89a',override=None):
    global_palette=None if no_global else palette
    flags=128+int(math.log2(len(palette)))-1 if global_palette else 0
    header=b'GIF'+version+struct.pack('<HHBBB',sw,sh,flags,1,0)
    table=bytes(sum((list(x) for x in global_palette),[])) if global_palette else b''
    gce=b'' if transparent is None else b'!\xf9\x04\x05\x03\0'+bytes([transparent])+b'\0'
    minimum=max(2,int(math.log2(len(palette))))
    body=frame(w,h,values,left=left,top=top,palette=palette if local else None,minimum=minimum,interlace=interlace,split=split,interval=interval,override=override)
    expected=[0]*(sw*sh)
    for y in range(h):
        for x in range(w):
            i=values[y*w+x];r,g,b=palette[i]
            expected[(y+top)*sw+x+left]=(r<<24)|(g<<16)|(b<<8)|(0 if i==transparent else 255)
    return header+table+extensions+gce+body+b';',expected


def corpus():
    valid=[];bad=[]
    for colors in [2,4,8,16,32,64,128,256]:
        palette=[tuple(RNG.randrange(256) for _ in range(3)) for _ in range(colors)]
        for w,h in [(1,1),(3,2),(7,3),(9,9),(13,17)]:
            values=[RNG.randrange(colors) for _ in range(w*h)]
            for interlace in [False,True]:
                for local,no_global in [(False,False),(True,False),(True,True)]:
                    for transparent in [None,0]:
                        data,pixels=gif(w+3,h+2,w,h,values,palette=palette,local=local,no_global=no_global,left=2,top=1,transparent=transparent,interlace=interlace,split=1 if local else 255)
                        valid.append((f'{colors}/{w}x{h}/{interlace}/{local}/{no_global}/{transparent}',data,w+3,h+2,pixels))
    palette=[(30,40,50),(60,70,80),(90,100,110),(120,130,140)]
    for w,h in [(500,100),(1,4096)]:
        for mode in ['random','runs','alternating']:
            values=[RNG.randrange(4) if mode=='random' else 0 if mode=='runs' else i%2 for i in range(w*h)]
            for interval in [0,1023,20000]:
                data,pixels=gif(w,h,w,h,values,palette=palette,interval=interval,interlace=True)
                valid.append((f'growth/{w}/{mode}/{interval}',data,w,h,pixels))
    extensions=[b'',b'!\xfe'+blocks(b'a comment',2),b'!\xff\x0bNETSCAPE2.0\x03\x01\0\0\0',b'!\x01\x0c'+b'\0'*12+blocks(b'ignored text')]
    for ext in extensions:
        for version in [b'87a',b'89a']:
            data,pixels=gif(4,2,4,2,[0,1,2,3]*2,palette=palette,extensions=ext,version=version)
            valid.append(('extensions/'+str(ext)+str(version),data,4,2,pixels))
    data,pixels=gif(4,2,4,2,[0,1,2,3]*2,palette=palette)
    second=frame(4,2,[3]*8,minimum=2)
    valid.append(('first animation frame',data[:-1]+second+b';',4,2,pixels))
    valid.append(('first frame ignores later malformed image',data[:-1]+b',',4,2,pixels))
    # Local table wins over a deliberately different global table.
    data,pixels=gif(4,2,4,2,[0,1,2,3]*2,palette=palette,local=True)
    changed=bytearray(data);changed[13:25]=b'\0'*12
    valid.append(('local overrides global',bytes(changed),4,2,pixels))
    base=valid[-1][1]
    for cut in range(len(base)-1):bad.append((base[:cut],None))
    for pos,value,error in [(6,0,'dimensions'),(8,0,'dimensions')]:
        changed=bytearray(base);struct.pack_into('<H',changed,pos,value);bad.append((bytes(changed),error))
    for wrong in [b'BAD89a',b'GIF88a']:
        bad.append((wrong+base[6:],'signature'))
    image=base.index(b',',25)
    for pos,value in [(image+1,5),(image+3,3),(image+5,0),(image+7,0)]:
        changed=bytearray(base);struct.pack_into('<H',changed,pos,value);bad.append((bytes(changed),'bounds'))
    lzw=image+10+12
    for minimum in [0,1,9,255]:
        changed=bytearray(base);changed[lzw]=minimum;bad.append((bytes(changed),'size'))
    for stream,error in [([4,6,5],'code'),([0,5],'code'),([4,0,5],'length'),([4,0,1,2,3,0,1,2,3,0,5],'length'),([4,0,1,2,3,0,1,2,3],'end')]:
        data,_=gif(4,2,4,2,[0]*8,palette=palette,override=packed(stream,2));bad.append((data,error))
    data,_=gif(1,1,1,1,[0],palette=palette[:2],override=packed([4,2,5],2));bad.append((data,'palette'))
    for packed_gce in [b'!\xf9\x03\0\0\0\0',b'!\xf9\x04\xe0\0\0\0\0']:
        data,_=gif(1,1,1,1,[0],palette=palette,extensions=packed_gce);bad.append((data,'block'))
    assert set(range(3,13))<=WIDTHS,WIDTHS
    assert SPECIALS>0
    assert FULL_RESETS>0
    return valid,bad


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--photon',type=Path,default=ROOT/'build/photon/photon_rs.js')
    parser.add_argument('--no-build',action='store_true')
    parser.add_argument('--prefix',default='build/gif')
    args=parser.parse_args()
    assert json.loads((args.photon.parent/'package.json').read_text())['version']=='0.3.4'
    if not args.no_build:
        compiler=os.environ.get('BEND',str(ROOT/'build/bend-native-toolchain/bend2/main.ts'))
        subprocess.run([compiler,'tests/gif.bend','-o',args.prefix+'.js'],cwd=ROOT,check=True)
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','tests/gif.bend',args.prefix],cwd=ROOT,check=True)
    valid,bad=corpus()
    with tempfile.TemporaryDirectory(prefix='gif-oracle-') as directory:
        files=[]
        for i,(_,data,_,_,_) in enumerate(valid):
            path=Path(directory)/f'{i}.gif';path.write_bytes(data);files.append(str(path))
        for start in range(0,len(valid),24):
            result=subprocess.run(['bun',str(ROOT/'tests/png_reference.cjs'),str(args.photon),*files[start:start+24]],text=True,capture_output=True,timeout=60)
            assert result.returncode==0,(start,result.stderr)
            records=[json.loads(line) for line in result.stdout.splitlines()]
            assert len(records)==len(valid[start:start+24])
            for got,(label,_,w,h,pixels) in zip(records,valid[start:start+24]):
                raw=got['rgba'];actual=[int.from_bytes(bytes(raw[i:i+4]),'big') for i in range(0,len(raw),4)]
                assert (got['width'],got['height'],actual)==(w,h,pixels),(label,actual[:30],pixels[:30])
    print(f'Photon: {len(valid)} images match independent pixels; LZW widths{sorted(WIDTHS)}, KwKwK cases{SPECIALS}, full resets{FULL_RESETS}',flush=True)
    cases=[]
    for label,data,w,h,pixels in valid:
        if len(pixels)>1000:
            digest=2166136261
            for pixel in pixels:digest=((digest*16777619)&0xffffffff)^pixel
            cases.append(('#'+data.hex(),f'{w}:{h}:hash:{digest}',label))
        else:cases.append((data.hex(),f'{w}:{h}:'+','.join(map(str,pixels)),label))
    cases += [(data.hex(),'error:'+error if error else 'error:',f'malformed-{i}') for i,(data,error) in enumerate(bad)]
    cases += [('invalid','error:byte','invalid-byte'),('@'+valid[0][1].hex(),'error:limit','pixel-budget')]
    for backend,command in [('bun',['bun',str(ROOT/(args.prefix+'.js'))]),('native-1',[str(ROOT/args.prefix),'--threads','1']),('native-4',[str(ROOT/args.prefix),'--threads','4'])]:
        for start in range(0,len(cases),24):
            batch=cases[start:start+24]
            actual=subprocess.check_output(command+[x[0] for x in batch],text=True,timeout=90).splitlines()
            assert len(actual)==len(batch),(backend,start,len(actual))
            for got,(_,wanted,label) in zip(actual,batch):
                assert got==wanted or wanted=='error:' and got.startswith(wanted),(backend,label,got,wanted)
        print(f'{backend}: {len(valid)} valid + {len(bad)+2} malformed/budget cases passed',flush=True)


if __name__=='__main__':main()
