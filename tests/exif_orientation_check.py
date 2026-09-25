"""Bounded EXIF parsing and shared raster orientation against pinned Pi source."""
from upstream_pin import UPSTREAM
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def tiff(value=1, endian='<', padding=0, before=0, after=0, tag_type=3, count=1):
    entry = lambda tag, kind, n, v: struct.pack(endian+'HHIHH', tag, kind, n, v, 0)
    entries = [entry(100, 3, 1, 7)]*before
    if value is not None:
        entries += [entry(274, tag_type, count, value)]
    entries += [entry(101, 3, 1, 9)]*after
    return (b'II' if endian == '<' else b'MM') + struct.pack(endian+'HI', 42, 8+padding) + b'\0'*padding + struct.pack(endian+'H', len(entries)) + b''.join(entries) + b'\0'*4


def segment(payload, marker=225):
    return b'\xff'+bytes([marker])+struct.pack('>H',len(payload)+2)+payload


def jpeg(payload, prefix=b'', suffix=b'\xff\xd9'):
    return b'\xff\xd8'+prefix+segment(b'Exif\0\0'+payload)+suffix


def chunk(payload, kind=b'EXIF'):
    return kind+struct.pack('<I',len(payload))+payload+b'\0'*(len(payload)%2)


def riff(chunks):
    return b'RIFF'+struct.pack('<I',len(chunks)+4)+b'WEBP'+chunks


def corpus():
    valid = [b'', b'unknown', b'\xff\xd8\xff\xd9', riff(b''), jpeg(b'II'+struct.pack('<HI',42,0)), jpeg(b'MM'+struct.pack('>HI',42,0))]
    for endian in ['<','>']:
        for value in [None,*range(1,9)]:
            for padding in [0,1,8]:
                data=tiff(value,endian,padding,2,2)
                valid += [jpeg(data),jpeg(data,segment(b'no metadata')+segment(b'JFIF',224)+b'\xff'),
                          riff(chunk(data)),riff(chunk(b'Exif\0\0'+data)),
                          riff(chunk(b'odd',b'JUNK')+chunk(data)+chunk(b'',b'VP8 '))]
    # A long directory and marker/chunk chain exercise forward traversal.
    valid += [jpeg(tiff(8,before=3000)),jpeg(tiff(6),segment(b'x',224)*2000),
              riff(chunk(b'x',b'JUNK')*2000+chunk(tiff(7)))]
    bad=[]
    def reject(data, error): bad.append((data.hex(),'error:'+error))
    for endian in ['<','>']:
        for data in [b'',b'II',b'XX'+tiff()[2:],(b'II' if endian=='<' else b'MM')+struct.pack(endian+'HI',43,8)]:
            reject(jpeg(data),'tiff');reject(riff(chunk(data)),'tiff')
        for position in [1,7,9,0x7fffffff,0x80000000,0xffffffff]:
            data=(b'II' if endian=='<' else b'MM')+struct.pack(endian+'HI',42,position)
            reject(jpeg(data),'tiff');reject(riff(chunk(data)),'tiff')
        for value in [0,9,65535]:
            reject(jpeg(tiff(value,endian)),'orientation')
        for kind,count in [(1,1),(4,1),(3,0),(3,2),(3,0xffffffff)]:
            reject(riff(chunk(tiff(3,endian,tag_type=kind,count=count))),'orientation')
        data=tiff(6,endian)
        for end in range(8,len(data)):
            reject(jpeg(data[:end]),'tiff')
        duplicated=data[:8]+struct.pack(endian+'H',2)+data[10:22]*2+data[22:]
        reject(jpeg(duplicated),'duplicate')
        # Offset/entry must not read into a later segment or chunk.
        reject(jpeg(data[:8],suffix=segment(data[8:])),'tiff')
        reject(riff(chunk(data[:8])+chunk(data[8:],b'JUNK')),'tiff')
    reject(b'\xff\xd8\xff\xe1\x00\x01','container')
    reject(b'\xff\xd8\xff\xe1\xff\xffExif\0\0','truncated')
    reject(b'\xff\xd8\x00\x00','container')
    for size in [0,3,5,0x7fffffff,0x80000000,0xffffffff]:
        data=b'RIFF'+struct.pack('<I',size)+b'WEBP'
        reject(data,'container' if size<4 else 'truncated')
    reject(riff(b'EXIF'+struct.pack('<I',0xffffffff)),'truncated')
    reject(riff(b'JUNK'+struct.pack('<I',0xffffffff)),'truncated')
    odd=tiff(4,padding=1)
    reject(riff(b'EXIF'+struct.pack('<I',len(odd))+odd),'truncated')
    reject(riff(b'JUNK'+struct.pack('<I',1)+b'x'),'truncated')
    reject(riff(chunk(tiff(6)))+b'x','container')
    bad += [('invalid','error:byte'),('invalid-tail','error:byte')]
    return list(dict.fromkeys(valid)),bad


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference',type=Path,default=UPSTREAM)
    parser.add_argument('--no-build',action='store_true')
    args=parser.parse_args()
    prefix=ROOT/'build/exif-orientation'
    if not args.no_build:
        compiler=os.environ.get('BEND',str(ROOT/'build/bend-native-toolchain/bend2/main.ts'))
        subprocess.run([compiler,'tests/exif-orientation.bend','-o',str(prefix)+'.js'],cwd=ROOT,check=True)
        subprocess.run(['sh','scripts/build-pure.sh','tests/exif-orientation.bend',str(prefix)],cwd=ROOT,check=True)
    valid,bad=corpus()
    inputs=ROOT/'build/exif-inputs.json'
    inputs.write_text(json.dumps([x.hex() for x in valid]))
    source=(args.reference/'packages/coding-agent/src/utils/exif-orientation.ts').read_text()
    oracle=ROOT/'build/exif-oracle.ts'
    # Type-only imports are removed by Bun. Production parser and geometry remain verbatim.
    oracle.write_text(source+'''
class Raster {
 constructor(public pixels:Uint8Array,public width:number,public height:number){}
 get_width(){return this.width} get_height(){return this.height} get_raw_pixels(){return this.pixels}
}
function flip(image:Raster,horizontal:boolean){
 const old=image.pixels.slice(),w=image.width,h=image.height;
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const from=((horizontal?y:h-1-y)*w+(horizontal?w-1-x:x))*4;
  image.pixels.set(old.subarray(from,from+4),(y*w+x)*4);
 }
}
const photon={PhotonImage:Raster,fliph:(image)=>flip(image,true),flipv:(image)=>flip(image,false)};
const cases=await Bun.file(process.argv[2]).json();
console.log(JSON.stringify(cases.map(hex=>{
 const bytes=Buffer.from(hex,'hex');
 const image=applyExifOrientation(photon as any,new Raster(Uint8Array.from({length:24},(_,i)=>i+1),3,2) as any,bytes);
 const data=image.get_raw_pixels(); const values=[];
 for(let i=0;i<data.length;i+=4)values.push(new DataView(data.buffer,data.byteOffset+i,4).getUint32(0));
 return [String(getExifOrientation(bytes)),`${image.get_width()}:${image.get_height()}:${values.join(',')}`];
})));
''')
    expected=json.loads(subprocess.check_output(['bun',str(oracle),str(inputs)],text=True))
    cases=[(value.hex(),expect[0]) for value,expect in zip(valid,expected)]
    cases += [('@'+value.hex(),expect[1]) for value,expect in zip(valid,expected)] + bad
    applied_bad=[('@'+value,error) for value,error in bad if not value.startswith('invalid')]
    cases += applied_bad
    for backend,command in [('bun',['bun',str(prefix)+'.js']),('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4'])]:
        for start in range(0,len(cases),25):
            batch=cases[start:start+25]
            actual=subprocess.check_output(command+[x[0] for x in batch],text=True,timeout=45).splitlines()
            wanted=[x[1] for x in batch]
            assert actual==wanted,(backend,start,[(start+i,a,b) for i,(a,b) in enumerate(zip(actual,wanted)) if a!=b])
        print(f'{backend}: {len(valid)} pinned parser + {len(valid)} pinned orientation + {len(bad)} strict malformed parse + {len(applied_bad)} malformed apply cases passed')


if __name__=='__main__': main()
