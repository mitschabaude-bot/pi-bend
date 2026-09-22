#!/usr/bin/env python3
"""JPEG differential decoding against pinned Photon 0.3.4 and source-pixel fixtures.

Test generation uses Pillow 12.3.0 (only in this test, never production).
See jpeg.md for coverage, compatibility changes and reproduction commands.
"""
import argparse,base64,io,json,random,subprocess,tempfile
from pathlib import Path
from PIL import Image
from jpeg_fixtures import baseline,lossless,mjpeg,marker,segments
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',default='build/jpeg');p.add_argument('--photon',default='build/photon/photon_rs.js');a=p.parse_args()
module=(ROOT/a.photon).resolve();assert json.loads((module.parent/'package.json').read_text())['version']=='0.3.4'
rng=random.Random(81310);fixtures=[]
def add(label,data,expected=None,corrected=False):fixtures.append((label,data,expected,corrected))
for mode in ['RGB','L','CMYK']:
 for progressive in [False,True]:
  for sub in ([0,1,2] if mode=='RGB' else [0]):
   for w,h in [(1,1),(1,17),(17,1),(7,5),(9,11),(17,19),(48,33)]:
    for quality in [1,83,100]:
     im=Image.frombytes(mode,(w,h),bytes(rng.randrange(256) for _ in range(w*h*len(mode))));o=io.BytesIO();im.save(o,'JPEG',progressive=progressive,subsampling=sub,quality=quality)
     add(f'{mode} {w}x{h} progressive={progressive} sub={sub} q={quality}',o.getvalue())
for progressive in [False,True]:
 for interval in [1,3,8]:
  im=Image.frombytes('RGB',(31,19),bytes(rng.randrange(256) for _ in range(31*19*3)));o=io.BytesIO();im.save(o,'JPEG',progressive=progressive,restart_marker_blocks=interval)
  add(f'restart {progressive} {interval}',o.getvalue())
for sampling in [[(3,1),(1,1),(1,1)],[(1,3),(1,1),(1,1)],[(4,1),(1,1),(1,1)],[(4,2),(1,1),(1,1)],[(2,1),(1,2),(1,1)],[(1,2),(1,1),(1,1)],[(1,1)]*3]:
 for separate in [False,True]:
  for restart in [0,3]:add(f'sampling {sampling} separate={separate} restart={restart}',baseline(43,35,sampling,separate=separate,interval=restart))
for ids,adobe in [([82,71,66],None),([9,8,7],0),([1,2,3],0),([9,8,7],1),([1,2,3,4],None),([1,2,3,4],0),([1,2,3,4],2)]:
 add(f'color {ids} adobe={adobe}',baseline(19,21,[(1,1)]*len(ids),ids=ids,adobe=adobe))
for wide in [False,True]:
 for mode in [192,193]:add(f'quantizer wide={wide} mode={mode}',baseline(23,17,[(1,1)]*3,wide=wide,mode=mode))
for original in [fixtures[9],fixtures[43]]:add('MJPEG defaults '+original[0],mjpeg(original[1]))
for precision,components in [(8,1),(16,1),(8,3),(8,4)]:
 for pred in range(1,8):
  w,h=5,3;pixels=[rng.randrange(1<<precision) for _ in range(w*h*components)]
  add(f'lossless {precision} components={components} predictor={pred}',lossless(w,h,components,precision,pred,0,0,pixels))
# Standards-correct restoration differs from Photon for these valid point
# transforms/restarts. Expected pixels come from the source encoder input.
for precision in [8,16]:
 for pred in range(1,8):
  for low,interval in [(1,0),(0,5),(1,5)]:
   w,h=5,3;pixels=[((20+i*4)<<(precision-8)) for i in range(w*h)]
   expected=[((v*255+32767)//65535 if precision==16 else v) for v in pixels]
   rgba=[(v<<24)|(v<<16)|(v<<8)|255 for v in expected]
   add(f'corrected lossless {precision} predictor={pred} low={low} interval={interval}',lossless(w,h,1,precision,pred,low,interval,pixels),(w,h,rgba),True)

for precision in [8,16]:
 values=[0,(1<<precision)-1,1<<(precision-1),(1<<(precision-1))-1,0,(1<<precision)-1]
 add(f'lossless {precision} boundaries',lossless(3,2,1,precision,1,0,0,values))
for size in [(128,129),(256,256)]:
 im=Image.frombytes('RGB',size,bytes(rng.randrange(256) for _ in range(size[0]*size[1]*3)));o=io.BytesIO();im.save(o,'JPEG',quality=20,progressive=True)
 add(f'larger progressive {size}',o.getvalue())

reference=[];differences=0
with tempfile.TemporaryDirectory(prefix='jpeg-oracle-') as tmp:
 paths=[]
 for i,(_,data,_,_) in enumerate(fixtures):
  path=Path(tmp)/f'{i}.json';path.write_text(json.dumps({'jpeg':base64.b64encode(data).decode()}));paths.append(str(path))
 for start in range(0,len(paths),16):
  run=subprocess.run(['bun',str(ROOT/'tests/jpeg_reference.cjs'),str(module),*paths[start:start+16]],capture_output=True,text=True,timeout=90)
  assert run.returncode==0,(start,run.stderr)
  for item in map(json.loads,run.stdout.splitlines()):reference.append((item['width'],item['height'],[int.from_bytes(bytes(item['rgba'][i:i+4]),'big') for i in range(0,len(item['rgba']),4)]))
assert len(reference)==len(fixtures)
for i,(label,_,expected,corrected) in enumerate(fixtures):
 if expected is not None:
  if reference[i]!=expected: differences+=1;assert corrected,label
  reference[i]=expected
assert differences>0,'independent corrected fixtures must expose the documented reference bug'

def command(data,limit):return str(limit)+':'+','.join(map(str,data))
commands=[];expected=[]
for (label,data,_,_),result in zip(fixtures,reference):
 w,h,_=result;commands.extend([command(data,w*h),command(data,w*h-1)]);expected.extend([(label,result),(label+' budget','limit')])
# Framing, malformed trees/scans and strict rejection of incomplete input.
seed=fixtures[50][1]
for i in sorted(set(list(range(min(65,len(seed))))+list(range(max(0,len(seed)-12),len(seed))))):
 commands.append(command(seed[:i],100000));expected.append((f'truncated {i}','error'))
for label,data in [('trailing',seed+b'\0'),('signature',b'\0'+seed[1:]),('zero frame',marker(216,b'')+b'\xff\xd9')]:commands.append(command(data,100000));expected.append((label,'error'))
valid=baseline(19,21,[(1,1)]*3,interval=1)
parts=segments(valid)
def malformed(label,data):commands.append(command(data,100000));expected.append((label,'error'))
for kind,offset,end,scan_end in parts:
 if kind in (196,219):malformed(f'missing table {kind}',valid[:offset]+valid[end:])
 if kind==192:
  for label,where,value in [('zero precision',offset+4,0),('zero horizontal sampling',offset+11,1),('zero vertical sampling',offset+11,16),('duplicate component ID',offset+13,1),('invalid quantizer ID',offset+12,4)]:
   bad=bytearray(valid);bad[where]=value;malformed(label,bytes(bad))
  for label,where in [('zero height',offset+5),('zero width',offset+7)]:
   bad=bytearray(valid);bad[where:where+2]=b'\0\0';malformed(label,bytes(bad))
  bad=bytearray(valid);bad[offset+5:offset+9]=b'\xff'*4;commands.append(command(bytes(bad),1));expected.append(('dimensions exceed budget','limit'))
 if kind==196:
  malformed('oversubscribed Huffman',valid[:offset]+marker(196,bytes([0,3]+[0]*15+[0,1,2]))+valid[end:])
  malformed('empty Huffman',valid[:offset]+marker(196,bytes([0]*17))+valid[end:])
  malformed('truncated Huffman counts',valid[:offset]+marker(196,b'\0\1')+valid[end:])
 if kind==219:
  bad=bytearray(valid);bad[offset+5]=0;malformed('zero quantizer',bytes(bad))
 if kind==218:
  malformed('duplicate sequential scan',valid[:scan_end]+valid[offset:scan_end]+valid[scan_end:])
  for label,where,value in [('unknown scan component',offset+5,99),('invalid sequential spectral end',end-2,62),('invalid sequential approximation',end-1,16)]:
   bad=bytearray(valid);bad[where]=value;malformed(label,bytes(bad))
  entropy=valid[end:scan_end];rst=entropy.find(b'\xff\xd0')
  assert rst>=0
  bad=bytearray(valid);bad[end+rst+1]=211;malformed('wrong restart number',bytes(bad))
  malformed('missing restart marker',valid[:end+rst]+valid[end+rst+2:])
malformed('lossless predictor zero',lossless(3,2,1,8,0,0,0,[20]*6))
malformed('lossless partial-row restart interval',lossless(3,2,1,8,1,0,2,[20]*6))
commands.append('100:256,216');expected.append(('invalid octet','byte'))
for backend in a.backends:
 executable=['bun',str(ROOT/(a.prefix+'.js'))] if backend=='bun' else [str(ROOT/a.prefix),'--threads',backend.split('-')[1]]
 count=0
 for start in range(0,len(commands),8):
  run=subprocess.run(executable+commands[start:start+8],capture_output=True,text=True,timeout=90)
  assert run.returncode==0,(backend,start,run.stderr)
  lines=run.stdout.splitlines();assert len(lines)==min(8,len(commands)-start),(backend,start,run.stdout,run.stderr)
  for text,(label,wanted) in zip(lines,expected[start:start+8]):
   if isinstance(wanted,str):assert text.startswith('error ') and (wanted=='error' or text=='error '+wanted),(backend,label,text,wanted)
   else:
    assert text.startswith('ok '),(backend,label,text)
    values=list(map(int,text[3:].split(',')));actual=(values[0],values[1],values[2:])
    assert actual==wanted,(backend,label,[(i,hex(x),hex(y)) for i,(x,y) in enumerate(zip(actual[2],wanted[2])) if x!=y][:8])
   count+=1
 print(f'{backend}: {len(fixtures)} image fixtures, {count} exact pixel/budget/malformed checks; {differences} corrected lossless reference discrepancies')
