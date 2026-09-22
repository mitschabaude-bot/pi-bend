#!/usr/bin/env python3
"""Native PNG pixel roundtrips, filter oracle, budgets and output-size differences.

Compile tests/png-encode.bend to build/png-encode.{js,c}/native first. The pinned
Photon test dependency can be fetched by tests/png_check.py --fetch-oracle.
"""
import argparse
import base64
import json
import random
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);p.add_argument('--prefix',default='build/png-encode');p.add_argument('--photon',default='build/photon/photon_rs.js');a=p.parse_args()
module=(ROOT/a.photon).resolve();assert module.exists(),'Fetch pinned oracle with tests/png_check.py --fetch-oracle'
assert json.loads((module.parent/'package.json').read_text())['version']=='0.3.4'
rng=random.Random(1954);fixtures=[]

def add(label,w,h,pixels,mode='pixels',value=None):fixtures.append((label,w,h,pixels,mode,value))
for w,h in [(1,1),(1,9),(9,1),(2,3),(7,5),(31,19),(64,64)]:
 for value in [0,0xffffffff,0x010203ff,0xdeadbe80]:add('solid',w,h,[value]*(w*h),'solid',value)
 add('random',w,h,[rng.getrandbits(32) for _ in range(w*h)])
 add('gradient',w,h,[((x*7)%256)<<24|((y*11)%256)<<16|((x+y)%256)<<8|255 for y in range(h) for x in range(w)])
 add('stripes',w,h,[0x123456ff if (x//3+y//5)%2 else 0xabcdef00 for y in range(h) for x in range(w)])
for w,h in [(129,129),(257,128)]:
 state=12345;pixels=[]
 for _ in range(w*h):
  state^=(state<<13)&0xffffffff;state^=state>>17;state^=(state<<5)&0xffffffff;pixels.append(state)
 add('large incompressible',w,h,pixels,'random',12345)
add('large repetitive',256,256,[0x010203ff]*65536,'solid',0x010203ff)


def png_data(png):
 assert png[:8]==b'\x89PNG\r\n\x1a\n'
 offset=8;packed=bytearray();kinds=[]
 while offset<len(png):
  n=struct.unpack_from('>I',png,offset)[0];kind=png[offset+4:offset+8];data=png[offset+8:offset+8+n]
  assert zlib.crc32(kind+data)==struct.unpack_from('>I',png,offset+8+n)[0]
  kinds.append(kind)
  if kind==b'IHDR':header=struct.unpack('>IIBBBBB',data)
  if kind==b'IDAT':packed.extend(data)
  offset+=n+12
 assert offset==len(png) and kinds[0]==b'IHDR' and kinds[-1]==b'IEND'
 return header,zlib.decompress(packed)


def paeth(a,b,c):
 p=a+b-c
 return min([(abs(p-a),0,a),(abs(p-b),1,b),(abs(p-c),2,c)])[2]


def unfilter(w,h,raw):
 assert len(raw)==h*(w*4+1)
 result=[];previous=bytes(w*4);offset=0
 for _ in range(h):
  kind=raw[offset];offset+=1;row=bytearray();assert 0<=kind<=4
  for i in range(w*4):
   left=row[i-4] if i>=4 else 0;above=previous[i];upper=previous[i-4] if i>=4 else 0
   row.append((raw[offset]+[0,left,above,(left+above)//2,paeth(left,above,upper)][kind])%256);offset+=1
  result.extend(int.from_bytes(row[i:i+4],'big') for i in range(0,len(row),4));previous=row
 return result


def oracle(requests,directory,label):
 paths=[]
 for i,request in enumerate(requests):
  path=Path(directory)/f'{label}-{i}.json';path.write_text(json.dumps(request));paths.append(str(path))
 output=[]
 for start in range(0,len(paths),16):
  run=subprocess.run(['bun',str(ROOT/'tests/png_encode_reference.cjs'),str(module),*paths[start:start+16]],capture_output=True,text=True,timeout=90)
  assert run.returncode==0,run.stderr
  output.extend(json.loads(line) for line in run.stdout.splitlines())
 assert len(output)==len(requests)
 return output


def command(fixture,limit):
 _,w,h,pixels,mode,value=fixture
 return f'{mode}:{w}:{h}:{limit}:'+(','.join(map(str,pixels)) if mode=='pixels' else str(value))

reference={}
with tempfile.TemporaryDirectory(prefix='png-encode-oracle-') as directory:
 photon=oracle([{'width':w,'height':h,'pixels':pixels} for _,w,h,pixels,_,_ in fixtures],directory,'source')
 photon_pngs=[base64.b64decode(item['png']) for item in photon]
 for backend in a.backends:
  executable=['bun',str(ROOT/(a.prefix+'.js'))] if backend=='bun' else [str(ROOT/a.prefix),'--threads',backend.split('-')[1]]
  encoded=[];count=0;filter_matches=0
  for i,fixture in enumerate(fixtures):
   label,w,h,pixels,_,_=fixture;checksum=sum(pixels)&0xffffffff
   run=subprocess.run(executable+[command(fixture,10000000)],capture_output=True,text=True,timeout=90)
   assert run.returncode==0,(backend,label,run.stderr)
   status,actualsum,csv=run.stdout.strip().split(':');assert status=='ok' and int(actualsum)==checksum,(backend,i,run.stdout[:100])
   png=bytes(map(int,csv.split(',')));header,raw=png_data(png)
   assert header==(w,h,8,6,0,0,0) and unfilter(w,h,raw)==pixels,(backend,label)
   if i in reference:assert reference[i]==png,(backend,'nondeterminism',i)
   reference[i]=png;encoded.append(png)
   _,photon_raw=png_data(photon_pngs[i])
   # Photon switches to no-filter if its fast compressor chooses stored data.
   photon_filters=photon_raw[::w*4+1]
   if any(photon_filters):
    assert raw==photon_raw,(backend,label,'adaptive filter differs')
    filter_matches+=1
   run=subprocess.run(executable+[command(fixture,len(png)),command(fixture,len(png)-1),command(fixture,0),'roundtrip:'+command(fixture,len(png))],capture_output=True,text=True,timeout=90)
   assert run.returncode==0,run.stderr
   assert run.stdout.splitlines()==[f'ok:{checksum}:'+','.join(map(str,png)),f'error:limit:{checksum}',f'error:limit:{checksum}','roundtrip:ok'],(backend,label,run.stdout[:100])
   count+=5
  decoded=oracle([{'png':base64.b64encode(png).decode()} for png in encoded],directory,'encoded')
  for got,(_,w,h,pixels,_,_) in zip(decoded,fixtures):
   rgba=got['rgba'];actual=[int.from_bytes(bytes(rgba[i:i+4]),'big') for i in range(0,len(rgba),4)]
   assert (got['width'],got['height'],actual)==(w,h,pixels)
  for w,h in [(0,1),(1,0),(2,2),(65536,65536),(2147483648,1),(4294967295,4294967295)]:
   run=subprocess.run(executable+[f'invalid:{w}:{h}'],capture_output=True,text=True)
   assert run.returncode==0 and run.stdout.strip()==f'invalid:{w}:{h}:16909060',(backend,run.stdout,run.stderr)
   count+=1
  print(f'{backend}: {count} pixel/budget/resource checks; {filter_matches} exact Photon filter comparisons; {len(decoded)} Photon decodes pass',flush=True)
 for i in [0,34,35,47,48,49,50,51]:
  label,w,h,_,_,_=fixtures[i]
  print(f'{label} {w}x{h}: Bend {len(reference[i])} bytes; Photon {len(photon_pngs[i])} bytes',flush=True)
