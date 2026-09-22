"""WebP container, first-frame composition and ALPH filtering checks."""
import argparse
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
from webp_lossless_check import constant,webp,expected,packed,fixtures

ROOT=Path(__file__).resolve().parents[1]
def chunk(tag,data):return tag+struct.pack('<I',len(data))+data+b'\0'*(len(data)%2)
def riff(chunks):return b'RIFF'+struct.pack('<I',len(chunks)+4)+b'WEBP'+chunks
def u24(n):return n.to_bytes(3,'little')
def vp8x(w,h,flags):return chunk(b'VP8X',bytes([flags])+b'\0'*3+u24(w-1)+u24(h-1))
def animated(w,h,fw,fh,x,y,color,alpha,blend,background=0xaa332211,later=False):
    frame=u24(x//2)+u24(y//2)+u24(fw-1)+u24(fh-1)+u24(100)+bytes([0 if blend else 2])+chunk(b'VP8L',constant(fw,fh,color))
    anim=bytes([background&255,(background>>8)&255,(background>>16)&255,background>>24])+b'\0\0'
    tail=chunk(b'ANMF',frame) if later else b''
    return riff(vp8x(w,h,2|(16 if alpha else 0))+chunk(b'ANIM',anim)+chunk(b'ANMF',frame)+tail)

def alpha_expected(method,values):
    out=[]
    for i,v in enumerate(values):
        x=i%3;y=i//3
        if i==0:p=0
        elif y==0:p=out[-1]
        elif x==0:p=out[i-3]
        elif method==1:p=out[-1]
        elif method==2:p=out[i-3]
        else:p=max(0,min(255,out[-1]+out[i-3]-out[i-4]))
        if method==0:p=0
        out.append((p+v)&255)
    return [0x12345600|v for v in out]

def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--photon',default=str(ROOT/'build/photon/photon_rs.js'));p.add_argument('--threads',default='1');args=p.parse_args()
    runner=['bun',args.runner] if args.runner.endswith('.js') else [args.runner]
    env=dict(os.environ,BEND_THREADS=args.threads)
    cases=[]
    for name,w,h,data,pixels in fixtures():
        cases.append((name,webp(data)))
    for flags in [0,4,8,16,32,60]:
        body=vp8x(3,2,flags)+chunk(b'ICCP',b'profile')+chunk(b'VP8L',constant(3,2,0x80123456))+chunk(b'EXIF',b'Exif\0\0')+chunk(b'XMP ',b'<xmp/>')
        cases.append((f'extended-{flags}',riff(body)))
    for alpha in [False,True]:
        for blend in [False,True]:
            for opacity in [0,1,17,127,128,254,255]:
                for full in [False,True]:
                    w,h,fw,fh,x,y=(3,2,3,2,0,0) if full else (7,6,3,2,2,2)
                    cases.append((f'animated-{alpha}-{blend}-{opacity}-{full}',animated(w,h,fw,fh,x,y,(opacity<<24)|0x123456,alpha,blend,later=True)))
    with tempfile.TemporaryDirectory() as tmp:
        files=[]
        for i,(_,data) in enumerate(cases):
            path=Path(tmp)/f'{i}.webp';path.write_bytes(data);files.append(str(path))
        refs=subprocess.check_output(['bun',str(ROOT/'tests/png_reference.cjs'),str(Path(args.photon).resolve()),*files],text=True).splitlines()
        actual=[];commands=[]
        for i,((name,data),ref) in enumerate(zip(cases,refs)):
            r=json.loads(ref)
            commands.append('!'+files[i] if r['width']*r['height']>1000 else data.hex())
        for start in range(0,len(commands),32):actual+=subprocess.check_output([*runner,*commands[start:start+32]],text=True,env=env,timeout=180).splitlines()
        assert len(actual)==len(cases)==len(refs)
        for (name,data),line,ref in zip(cases,actual,refs):
            r=json.loads(ref);values=[int.from_bytes(bytes(r['rgba'][i:i+4]),'big') for i in range(0,len(r['rgba']),4)]
            wanted=expected(r['width'],r['height'],values,r['width']*r['height']>1000)
            assert line==wanted,(name,line[:150],wanted[:150])
    alpha=[];rng=random.Random(789)
    for method in range(4):
        for preprocessing in [0,16]:
            for values in [[0]*6,[255]*6,[1,128,255,17,250,99]]+[[rng.randrange(256) for _ in range(6)] for _ in range(8)]:
                alpha.append(('a'+bytes([method*4+preprocessing]+values).hex(),expected(3,2,alpha_expected(method,values))))
            for residual in [0,1,127,128,255]:
                stream=constant(3,2,residual<<8)[5:]
                alpha.append(('a'+(bytes([1+method*4+preprocessing])+stream).hex(),expected(3,2,alpha_expected(method,[residual]*6))))
    outputs=subprocess.check_output([*runner,*[v for v,_ in alpha]],text=True,env=env).splitlines()
    assert outputs==[v for _,v in alpha],next(((i,a,b) for i,(a,b) in enumerate(zip(outputs,[v for _,v in alpha])) if a!=b),None)
    # The pinned decoder has confirmed quantizer and chroma-edge defects.
    # For lossy files use libwebp YUV + the pinned RGB conversion, independently
    # preserving the encoder input's lossless alpha channel.
    lossy=[];lossy_expected=[]
    with tempfile.TemporaryDirectory() as tmp:
        paths=[];alpha_values=[]
        for w,h in [(1,1),(3,2),(17,19),(32,16)]:
            for opacity in [False,True]:
                raw=bytes(v for y in range(h) for x in range(w) for v in ((x*73+y*19)%256,(x*17+y*31)%256,(x*37+y*7)%256,(x*61+y*43)%256 if opacity else 255))
                encoded=subprocess.run(['ffmpeg','-loglevel','error','-f','rawvideo','-pixel_format','rgba','-video_size',f'{w}x{h}','-i','pipe:0','-frames:v','1','-c:v','libwebp','-quality','70','-threads','1','-f','webp','pipe:1'],input=raw,capture_output=True,check=True).stdout
                path=Path(tmp)/f'lossy-{w}-{h}-{opacity}.webp';path.write_bytes(encoded);paths.append(str(path));lossy.append(encoded.hex());alpha_values.append(raw[3::4])
        refs=subprocess.check_output(['python3',str(ROOT/'tests/vp8_libwebp_reference.py'),*paths],text=True).splitlines()
        for ref,alpha_bytes in zip(refs,alpha_values):
            r=json.loads(ref);lossy_expected.append(expected(r['width'],r['height'],[(p&0xffffff00)|a for p,a in zip(r['pixels'],alpha_bytes)]))
        outputs=subprocess.check_output([*runner,*lossy],text=True,env=env).splitlines()
        assert outputs==lossy_expected,next(((i,a[:150],b[:150]) for i,(a,b) in enumerate(zip(outputs,lossy_expected)) if a!=b),None)
    # Unknown RIFF metadata is permitted by WebP, including before image data.
    # The pinned parser inconsistently ignores only trailing unknown chunks.
    for tag in [b'JUNK',b'zzzz']:
        encoded=riff(vp8x(3,2,0)+chunk(tag,b'odd')+chunk(b'VP8L',constant(3,2,0xff123456)))
        line=subprocess.check_output([*runner,encoded.hex()],text=True,env=env).strip()
        assert line==expected(3,2,[packed(0xff123456)]*6)

    sample=cases[0][1]
    malformed=['invalid','', '00','@'+webp(constant(2,2,0)).hex()]
    malformed += [sample[:n].hex() for n in range(len(sample))]
    malformed += [riff(vp8x(3,2,flag)+chunk(b'VP8L',constant(3,2,0))).hex() for flag in [1,64,128]]
    malformed += [riff(vp8x(3,2,0)+chunk(b'VP8L',constant(2,2,0))).hex(),riff(vp8x(3,2,0)+chunk(b'ALPH',b'\0')).hex()]
    malformed += ['a'+bytes([header]+[0]*6).hex() for header in [2,3,32,64,128,255]]
    malformed += ['a'+bytes([0]+[0]*n).hex() for n in [0,1,5,7]]
    outputs=subprocess.check_output([*runner,*malformed],text=True,env=env).splitlines()
    assert len(outputs)==len(malformed) and all(v.startswith('error:') for v in outputs),outputs
    print(f'{len(cases)} Photon container/frame comparisons; {len(alpha)} independent ALPH checks; {len(lossy)} libwebp lossy/alpha files; 2 unknown chunks; {len(malformed)} boundary checks passed')

if __name__=='__main__':main()
