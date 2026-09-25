"""Native BMP against independently generated pixels and pinned Photon 0.3.4."""
import argparse
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
RNG=random.Random(941)


def bmp(w,h,depth,data,*,dib=40,compression=0,palette=(),masks=None,top=False,gap=b''):
    extra=b''
    if dib==12:
        header=struct.pack('<IHHHH',12,w,h,1,depth)
        colors=b''.join(bytes((b,g,r)) for r,g,b in palette)
    else:
        header=bytearray(struct.pack('<IiiHHIIiiII',dib,w,-h if top else h,1,depth,compression,len(data),0,0,len(palette),0)+b'\0'*(dib-40))
        if masks:
            fields=struct.pack('<III',*masks[:3])+(struct.pack('<I',masks[3]) if dib>=56 else b'')
            if dib==40: extra=fields
            else: header[40:40+len(fields)]=fields
        header=bytes(header)
        colors=b''.join(bytes((b,g,r,0)) for r,g,b in palette)
    offset=14+len(header)+len(extra)+len(colors)+len(gap)
    return b'BM'+struct.pack('<III',offset+len(data),0,offset)+header+extra+colors+gap+data


def rgba(r,g,b,a=255): return (r<<24)|(g<<16)|(b<<8)|a


def unpack_field(value,mask):
    if not mask:return 255
    shift=(mask&-mask).bit_length()-1
    bits=(mask>>shift).bit_length()
    shift+=max(0,bits-8);bits=min(8,bits)
    sample=(value>>shift)&((1<<bits)-1)
    if bits==7:return (sample<<1)|(sample>>6)
    maximum=(1<<bits)-1
    return (sample*255+maximum//2)//maximum


def generated(w,h,depth,*,dib=40,top=False,masks=None):
    palette=[(RNG.randrange(256),RNG.randrange(256),RNG.randrange(256)) for _ in range(1<<depth)] if depth<=8 else []
    pixels=[]; rows=[]
    for _ in range(h):
        values=[RNG.randrange(1<<depth) for _ in range(w)]
        row=b''
        if depth<=8:
            for start in range(0,w,8//depth):
                value=0
                for i in range(8//depth):value=(value<<depth)|(values[start+i] if start+i<w else 0)
                row+=bytes([value])
            pixels += [rgba(*palette[v]) for v in values]
        else:
            row=b''.join(v.to_bytes(depth//8,'little') for v in values)
            selected=masks or ((31744,992,31,0) if depth==16 else (0xff0000,0xff00,0xff,0))
            pixels += [rgba(*(unpack_field(v,m) for m in selected)) for v in values]
        rows.append(row+b'\0'*((-len(row))%4))
    data=b''.join(rows if top else reversed(rows))
    return bmp(w,h,depth,data,dib=dib,top=top,palette=palette,masks=masks,compression=3 if masks else 0,gap=b'gap'),pixels


def corpus():
    valid=[];bad=[]
    for dib in [12,40,52,56,108,124]:
        for depth in ([1,4,8,24] if dib==12 else [1,2,4,8,16,24,32]):
            for top in ([False] if dib==12 else [False,True]):
                for w,h in [(1,1),(3,2),(7,3),(8,1),(9,2),(17,5)]:
                    data,pixels=generated(w,h,depth,dib=dib,top=top)
                    valid.append((f'dib{dib}/{depth}/{top}/{w}x{h}',data,w,h,pixels))
    for dib in [40,52,56,108,124]:
        for depth,masks in [(16,(31744,992,31,0)),(16,(63488,2016,31,0)),(16,(0xf00,0xf0,0xf,0)),
                            (32,(0x3ff00000,0xffc00,0x3ff,0)),(32,(0xff000000,0xff0000,0xff00,0)),
                            (32,(1,6,56,0)),(32,(127,0x3f80,0x1fc000,0))]:
            for top in [False,True]:
                data,pixels=generated(9,3,depth,dib=dib,top=top,masks=masks)
                valid.append((f'bitfields/{dib}/{depth}/{masks}/{top}',data,9,3,pixels))
        if dib>=56:
            for depth,masks in [(16,(0xf00,0xf0,0xf,0xf000)),(32,(0xff0000,0xff00,0xff,0xff000000)),(32,(0x3ff00000,0xffc00,0x3ff,0xc0000000))]:
                data,pixels=generated(7,2,depth,dib=dib,masks=masks)
                valid.append((f'alpha/{dib}/{depth}/{masks}',data,7,2,pixels))
    for depth in [4,8]:
        palette=[(i*11%256,i*31%256,i*71%256) for i in range(1<<depth)]
        def rle(label,data,rows,w=7):
            pixels=[rgba(*palette[v]) if v is not None else 255 for row in reversed(rows) for v in row]
            valid.append((label,bmp(w,len(rows),depth,data,palette=palette,compression=2 if depth==4 else 1),w,len(rows),pixels))
        pattern=0x12 if depth==4 else 1
        seq=[1,2,1,2,1,2,1] if depth==4 else [1]*7
        rle('encoded runs',bytes([7,pattern,0,0,7,pattern,0,0]),[seq,seq])
        rle('early EOF',b'\0\1',[[None]*7]*3)
        rle('EOL gap',bytes([3,pattern,0,0,0,1]),[seq[:3]+[None]*4,[None]*7])
        rle('delta gap',bytes([2,pattern,0,2,1,1,2,pattern,0,1]),[seq[:2]+[None]*5,[None]*3+seq[:2]+[None]*2,[None]*7])
        for n in [3,4,5,6,7]:
            values=list(range(1,n+1))
            payload=bytes(values) if depth==8 else bytes([(values[i]<<4)|(values[i+1] if i+1<n else 0) for i in range(0,n,2)])
            data=bytes([0,n])+payload+b'\0'*(len(payload)%2)+b'\0\1'
            rle(f'absolute/{depth}/{n}',data,[values+[None]*(7-n)])
        for data in [bytes([8,pattern]),bytes([0,2,8,0]),bytes([0,2,0,1]),bytes([0,8])+b'\x11'*8]:
            bad.append((bmp(7,1,depth,data,palette=palette,compression=2 if depth==4 else 1),'rle'))
        for data in [b'',b'\0',b'\0\2',b'\0\2\1',b'\0\3',b'\0\3\x11']:
            bad.append((bmp(7,1,depth,data,palette=palette,compression=2 if depth==4 else 1),'truncated'))
        bad.append((bmp(7,1,depth,b'\0\1',palette=palette,compression=2 if depth==4 else 1,top=True),'unsupported'))
    palette=[(i,255-i,i//2) for i in range(256)]
    data=bmp(255,256,8,bytes([255,129,0,0])*256,palette=palette,compression=1)
    valid.append(('large RLE expansion',data,255,256,[rgba(*palette[129])]*(255*256)))
    for label,data,w,h,pixels in list(valid[24:36]):
        # Zero colors_used means the complete palette for this depth.
        if int.from_bytes(data[14:18],'little')!=12:
            changed=bytearray(data);changed[46:50]=b'\0'*4
            valid.append(('default palette/'+label,bytes(changed),w,h,pixels))
    base=generated(3,2,24)[0]
    for cut in range(2,len(base)):
        bad.append((base[:cut],None))
    for pos,value,error in [(14,11,'unsupported'),(14,64,'unsupported'),(18,0,'dimensions'),(18,0xffffffff,'dimensions'),(22,0x80000000,'dimensions'),(22,0,'dimensions'),(26,2,'header'),(28,3,'unsupported'),(30,4,'unsupported'),(10,53,'header'),(10,0xffffffff,'header')]:
        data=bytearray(base);struct.pack_into('<H' if pos in (26,28) else '<I',data,pos,value);bad.append((bytes(data),error))
    for depth in [0,9,15,48,65535]:
        data=bytearray(base);struct.pack_into('<H',data,28,depth);bad.append((bytes(data),'unsupported'))
    for masks in [(0,0xff00,0xff,0),(0xff0000,0xff0000,0xff,0),(0x550000,0xff00,0xff,0),(0xff0000,0xff00,0xff,0xff)]:
        bad.append((bmp(1,1,32,b'\0'*4,dib=56,compression=3,masks=masks),'masks'))
    bad.append((bmp(1,1,16,b'\0'*4,dib=52,compression=3,masks=(0xff0000,0xff00,0xff,0)),'masks'))
    bad.append((bmp(1,1,8,b'\1\0\0\0',palette=[(1,2,3)]),'palette'))
    bad.append((bmp(65535,1,8,bytes([0,2,0,255]),palette=[(1,2,3)],compression=1),'rle'))
    # Palette size, signed dimensions, masks, row extents are checked before allocation.
    return valid,bad


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--photon',type=Path,default=ROOT/'build/photon/photon_rs.js')
    parser.add_argument('--no-build',action='store_true')
    parser.add_argument('--prefix',default='build/bmp')
    args=parser.parse_args()
    assert json.loads((args.photon.parent/'package.json').read_text())['version']=='0.3.4'
    if not args.no_build:
        compiler=os.environ.get('BEND',str(ROOT/'build/bend-native-toolchain/bend2/main.ts'))
        subprocess.run([compiler,'tests/bmp.bend','-o',args.prefix+'.js'],cwd=ROOT,check=True)
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','tests/bmp.bend',args.prefix],cwd=ROOT,check=True)
    valid,bad=corpus()
    with tempfile.TemporaryDirectory(prefix='bmp-oracle-') as directory:
        files=[]
        for i,(_,data,_,_,_) in enumerate(valid):
            path=Path(directory)/f'{i}.bmp';path.write_bytes(data);files.append(str(path))
        for start in range(0,len(valid),32):
            result=subprocess.run(['bun',str(ROOT/'tests/png_reference.cjs'),str(args.photon),*files[start:start+32]],text=True,capture_output=True,timeout=60)
            assert result.returncode==0,(start,result.stderr)
            records=[json.loads(line) for line in result.stdout.splitlines()]
            for got,(label,_,w,h,pixels) in zip(records,valid[start:start+32]):
                raw=got['rgba'];actual=[int.from_bytes(bytes(raw[i:i+4]),'big') for i in range(0,len(raw),4)]
                assert (got['width'],got['height'],actual)==(w,h,pixels),(label,actual,pixels)
    print(f'Photon: {len(valid)} images match independent expected pixels',flush=True)
    cases=[]
    for label,data,w,h,pixels in valid:
        if len(pixels)>1000:
            digest=2166136261
            for pixel in pixels:digest=((digest*16777619)&0xffffffff)^pixel
            cases.append(('#'+data.hex(),f'{w}:{h}:hash:{digest}',label))
        else:cases.append((data.hex(),f'{w}:{h}:'+','.join(map(str,pixels)),label))
    cases += [(data.hex(),'error:'+error if error else 'error:',f'malformed-{i}') for i,(data,error) in enumerate(bad)]
    cases += [('invalid','error:byte','invalid-byte'),('@'+valid[1][1].hex(),'error:limit','pixel-budget')]
    for backend,command in [('bun',['bun',str(ROOT/(args.prefix+'.js'))]),('native-1',[str(ROOT/args.prefix),'--threads','1']),('native-4',[str(ROOT/args.prefix),'--threads','4'])]:
        for start in range(0,len(cases),25):
            batch=cases[start:start+25]
            actual=subprocess.check_output(command+[x[0] for x in batch],text=True,timeout=60).splitlines()
            assert len(actual)==len(batch),(backend,start,len(actual))
            for got,(_,wanted,label) in zip(actual,batch):
                assert got==wanted or wanted=='error:' and got.startswith(wanted),(backend,label,got,wanted)
        print(f'{backend}: {len(valid)} valid + {len(bad)+2} malformed/budget cases passed',flush=True)


if __name__=='__main__':main()
