"""Exact Lanczos3 pixel comparisons with pinned Photon 0.3.4."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('backends', nargs='*', default=['bun','native-1','native-4'])
parser.add_argument('--prefix', default='build/image-resize')
parser.add_argument('--photon', default='build/photon/photon_rs.js')
args = parser.parse_args()
photon = (ROOT/args.photon).resolve()
assert json.loads((photon.parent/'package.json').read_text())['version'] == '0.3.4'
oracle = ROOT/'build/image-resize-reference.cjs'
oracle.write_text(r'''
const fs=require('node:fs'), photon=require(process.argv[2]);
for(const [w,h,nw,nh] of JSON.parse(fs.readFileSync(0,'utf8'))) {
  const bytes=new Uint8Array(w*h*4), view=new DataView(bytes.buffer);
  for(let i=0;i<w*h;i++) view.setUint32(i*4,Math.imul(i,2654435761)>>>0);
  const image=new photon.PhotonImage(bytes,w,h);
  const result=photon.resize(image,nw,nh,photon.SamplingFilter.Lanczos3);
  const data=result.get_raw_pixels(), out=new DataView(data.buffer,data.byteOffset,data.byteLength);
  const pixels=Array.from({length:nw*nh},(_,i)=>out.getUint32(i*4));
  console.log(`${result.get_width()}:${result.get_height()}:${pixels.join(',')}`);
  result.free(); image.free();
}
''')
shapes = [(1,1),(1,9),(11,1),(2,3),(3,2),(7,9),(16,16),(31,29)]
cases = [(w,h,nw,nh) for w,h in shapes for nw,nh in shapes]
cases += [(97,53,1,1),(97,53,7,5),(17,19,23,29),(32,31,32,17)]
cases.append((1024,1024,512,512))
reference = subprocess.run(['node',str(oracle),str(photon)],input=json.dumps(cases),
                           text=True,capture_output=True,check=True).stdout.splitlines()
requests = [':'.join(map(str,(*case,100000))) for case in cases]
w,h,words = reference[-1].split(':')
checksum = 2166136261
for word in words.split(','):
    checksum = ((checksum * 16777619) & 0xffffffff) ^ int(word)
reference[-1] = f'{w}:{h}:hash:{checksum}'
requests[-1] = 'bench'
errors = {'3:2:0:2:100':'dimensions', '3:2:2:0:100':'dimensions',
          '3:2:2:2:3':'limit', '20:2:1:20:100':'limit',
          '3:2:4294967295:4294967295:100':'dimensions', 'invalid':'image'}
requests += list(errors)
reference += list(errors.values())
for backend in args.backends:
    command = ['bun',str(ROOT/(args.prefix+'.js'))] if backend=='bun' else [str(ROOT/args.prefix),'--threads',backend[-1]]
    actual = []
    for start in range(0,len(requests),8):
        result = subprocess.run(command+requests[start:start+8],text=True,capture_output=True,timeout=120)
        assert result.returncode == 0, (backend,result.stderr[-2000:])
        actual += result.stdout.splitlines()
    assert len(actual)==len(reference),(backend,len(actual),len(reference))
    mismatches = [(request,got,want) for request,got,want in zip(requests,actual,reference) if got!=want]
    if mismatches:
        (ROOT/'build/image-resize-mismatches.json').write_text(json.dumps(mismatches))
    assert not mismatches,(backend,len(mismatches),mismatches[0][0] if mismatches else '')
    print(f'{backend}: {len(cases)-1} exact Photon Lanczos3 images, 1024-to-512 ordered checksum, and {len(errors)} boundary cases PASS',flush=True)
