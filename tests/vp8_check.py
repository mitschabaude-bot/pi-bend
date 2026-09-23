#!/usr/bin/env python3
"""Encode fixtures with libwebp; compare independent decoded YUV/RGB pixels."""
import argparse,json,pathlib,random,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--cwebp',default='build/webp-tools/root/usr/bin/cwebp');p.add_argument('--photon',default='build/photon/photon_rs.js');p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();cmd=a.command
if cmd[:1]==['--']:cmd=cmd[1:]
assert cmd
rng=random.Random(53719)
def payload(blob):
 i=12
 while i<len(blob):
  size=int.from_bytes(blob[i+4:i+8],'little')
  if blob[i:i+4]==b'VP8 ':return blob[i+8:i+8+size]
  i+=8+size+(size%2)
 raise AssertionError('no VP8 payload')
def run(args):
 result=subprocess.run(cmd+args,text=True,capture_output=True)
 assert result.returncode==0,result.stderr[-2000:]
 lines=result.stdout.splitlines();assert len(lines)==len(args)
 return lines
# This valid stream exposes the pinned decoder's unsegmented quantizer defect.
red=pathlib.Path('tests/fixtures/webp/vp8-solid-red.webp')
red_expected=json.loads(subprocess.check_output(['python3','tests/vp8_libwebp_reference.py',str(red)],text=True))
red_photon=json.loads(subprocess.check_output(['node','tests/vp8_reference.cjs',str(pathlib.Path(a.photon).resolve()),str(red)],text=True))
red_decoded=run(['64:'+','.join(map(str,payload(red.read_bytes())))])[0]
assert list(map(int,red_decoded[3:].split(',')))==red_expected['pixels']
assert red_expected['pixels']==[0xff0002ff]*64
assert red_photon['pixels']==[0x996b6dff]*64
with tempfile.TemporaryDirectory(prefix='vp8-reference-') as temp:
 directory=pathlib.Path(temp);cases=[];files=[]
 for w,h in [(1,1),(7,9),(16,16),(31,27),(32,32),(65,33),(48,64)]:
  patterns=[bytes([255,0,0,255])*(w*h),bytes(rng.randrange(256) if i%4!=3 else 255 for i in range(w*h*4)),bytes(v for y in range(h) for x in range(w) for v in ((x*17)&255,(y*31)&255,((x+y)*11)&255,255))]
  for mode,pixels in enumerate(patterns):
   for quality in [5,30,75,95]:
    raw=directory/'input.rgba';raw.write_bytes(pixels);file=directory/f'{len(files)}.webp'
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgba','-video_size',f'{w}x{h}','-i',str(raw),'-frames:v','1','-c:v','libwebp','-quality',str(quality),'-compression_level',str(mode*3),str(file)],check=True)
    data=payload(file.read_bytes());cases.append((w,h,mode,quality,data));files.append(str(file))
 # libvpx supplies independent mode choices and all token partition counts.
 for w,h in [(16,16),(31,27),(64,64),(129,97)]:
  raw=directory/'input.rgba';raw.write_bytes(bytes(rng.randrange(256) if i%4!=3 else 255 for i in range(w*h*4)))
  for slices in [1,2,4,8]:
   ivf=directory/'input.ivf'
   subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgba','-video_size',f'{w}x{h}','-i',str(raw),'-frames:v','1','-c:v','libvpx','-pix_fmt','yuv420p','-g','1','-slices',str(slices),'-qmin','20','-qmax','20','-b:v','1M','-f','ivf',str(ivf)],check=True)
   encoded=ivf.read_bytes();size=int.from_bytes(encoded[32:36],'little');data=encoded[44:44+size]
   chunk=b'VP8 '+len(data).to_bytes(4,'little')+data+b'\0'*(len(data)%2)
   webp=b'RIFF'+(len(chunk)+4).to_bytes(4,'little')+b'WEBP'+chunk
   file=directory/f'{len(files)}.webp';file.write_bytes(webp)
   cases.append((w,h,3,slices,data));files.append(str(file))
 # The simple filter and nonzero sharpness are explicit encoder choices.
 for w,h in [(7,9),(32,32),(65,33)]:
  raw=directory/'input.yuv';raw.write_bytes(bytes(rng.randrange(256) for _ in range(w*h+2*((w+1)//2)*((h+1)//2))))
  for sharpness in [0,4,7]:
   for strength in [60,100]:
    file=directory/f'{len(files)}.webp'
    subprocess.run([a.cwebp,'-quiet','-s',str(w),str(h),'-q','25','-m','6','-f',str(strength),'-sharpness',str(sharpness),'-nostrong',str(raw),'-o',str(file)],check=True)
    data=payload(file.read_bytes());cases.append((w,h,4,sharpness,data));files.append(str(file))
 refs=[json.loads(line) for line in subprocess.check_output(['python3','tests/vp8_libwebp_reference.py',*files],text=True).splitlines()]
 outputs=[]
 for start in range(0,len(cases),10): outputs.extend(run([str(w*h)+':'+','.join(map(str,data)) for w,h,_,_,data in cases[start:start+10]]))
 failures=[]
 for i,(case,ref,line) in enumerate(zip(cases,refs,outputs)):
  assert line.startswith('ok:'),(i,case[:4],line)
  actual=list(map(int,line[3:].split(',')));expected=ref['pixels']
  assert len(actual)==len(expected)
  differences=[(j,x,y) for j,(x,y) in enumerate(zip(actual,expected)) if x!=y]
  if differences:failures.append((i,case[:4],len(differences),differences[:3]))
 headers=run(['header:'+','.join(map(str,c[-1])) for c in cases])
 counts={int(h.split(':')[0]) for h in headers};simple={int(h.split(':')[1]) for h in headers};segments={int(h.split(':')[2]) for h in headers}
 assert counts=={1,2,4,8},counts
 assert simple=={0,1},simple
 assert segments=={0,1},segments
 # Budget and structural failures must reject before producing a raster.
 w,h,_,_,data=cases[18]
 invalid=[(w*h-1,data,'error:limit'),(w*h,b'','error:truncated'),(w*h,bytes([data[0]|1])+data[1:],'error:interframe'),(w*h,bytes([data[0]|8])+data[1:],'error:version'),(w*h,bytes([data[0]&~16])+data[1:],'error:hidden'),(w*h,data[:6]+b'\0\0'+data[8:],'error:dimensions'),(w*h,data[:3]+b'bad'+data[6:],'error:signature'),(w*h,data[:10]+b'\xff'+data[11:],'error:color'),(w*h,data[:len(data)//2],'error:truncated')]
 got=run([str(limit)+':'+','.join(map(str,value)) for limit,value,_ in invalid]+[str(w*h)+':256'])
 assert got==[expected for _,_,expected in invalid]+['error:byte'],got
 print('coverage:',counts,'simple flags:',simple,'segmentation flags:',segments)
 if failures:
  pathlib.Path('build/vp8-failures.json').write_text(json.dumps(failures,indent=2))
  for i,*_ in failures:
   pathlib.Path(f'build/vp8-failing-{i}.webp').write_bytes(pathlib.Path(files[i]).read_bytes())
  raise AssertionError(f'{len(failures)}/{len(cases)} mismatches: {failures[:6]}')
 print(f'PASS {len(cases)+1} exact independent libwebp decoded-pixel comparisons and {len(invalid)+1} rejection cases')
