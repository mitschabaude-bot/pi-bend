"""Compare pixels with pinned Pi's actual EXIF orientation implementation."""
from upstream_pin import UPSTREAM
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--prefix', default='build/image-orientation')
args = parser.parse_args()
oracle = ROOT / 'build/image-orientation-oracle.mts'
source = UPSTREAM / 'packages/coding-agent/src/utils/exif-orientation.ts'
oracle.write_text('import { applyExifOrientation } from ' + json.dumps(str(source)) + ';\n' + r'''
class Image {
  constructor(public data: Uint8Array, public w: number, public h: number) {}
  get_width() { return this.w; }
  get_height() { return this.h; }
  get_raw_pixels() { return this.data; }
}
function flip(image: Image, horizontal: boolean) {
  const old = image.data.slice();
  for (let y=0;y<image.h;y++) for (let x=0;x<image.w;x++) {
    const from=((horizontal ? y : image.h-1-y)*image.w+(horizontal ? image.w-1-x : x))*4;
    image.data.set(old.subarray(from,from+4),(y*image.w+x)*4);
  }
}
const photon = {PhotonImage:Image,fliph:(i:Image)=>flip(i,true),flipv:(i:Image)=>flip(i,false)};
for (const [w,h,orientation] of JSON.parse(await Bun.stdin.text())) {
  const pixels = new Uint8Array(w*h*4);
  const view = new DataView(pixels.buffer);
  for(let i=0;i<w*h;i++) view.setUint32(i*4,Math.imul(i,2654435761)>>>0);
  // Valid JPEG APP1 containing little-endian TIFF with a single SHORT tag.
  const exif = new Uint8Array([255,216,255,225,0,34,69,120,105,102,0,0,
    73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,orientation,0,0,0,0,0,0,0,255,217]);
  const result=applyExifOrientation(photon as any,new Image(pixels,w,h) as any,exif);
  const bytes=result.get_raw_pixels();
  const output=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const words=Array.from({length:w*h},(_,i)=>output.getUint32(i*4));
  console.log(`${result.get_width()}:${result.get_height()}:${words.join(',')}`);
}
''')
cases = [(w, h, o) for w, h in [(1, 1), (1, 13), (17, 1), (2, 3),
         (3, 2), (7, 9), (16, 16), (31, 29)] for o in range(1, 9)]
cases.append((300, 257, 6))
reference = subprocess.run(['bun', str(oracle)], input=json.dumps(cases), text=True,
                           capture_output=True, check=True).stdout.splitlines()
requests = [':'.join(map(str, c)) for c in cases]
errors = {'0:3:1':'dimensions', '3:0:1':'dimensions', 'short':'pixels',
          'overflow':'dimensions', 'capacity':'pixels', '2:3:0':'orientation',
          '2:3:9':'orientation'}
large_width, large_height, words = reference[-1].split(':')
checksum = 2166136261
for word in words.split(','):
    checksum = ((checksum * 16777619) & 0xffffffff) ^ int(word)
reference[-1] = f'{large_width}:{large_height}:hash:{checksum}'
requests[-1] = 'large'
requests += list(errors)
reference += ['error:'+e for e in errors.values()]
for backend, command in [('Bun', ['bun', str(ROOT/(args.prefix+'.js'))]),
                         ('native1', [str(ROOT/args.prefix), '--threads', '1']),
                         ('native4', [str(ROOT/args.prefix), '--threads', '4'])]:
    actual = []
    for start in range(0, len(requests), 8):
        run = subprocess.run(command+requests[start:start+8], text=True,
                             capture_output=True, check=True, timeout=60)
        actual.extend(run.stdout.splitlines())
    assert len(actual) == len(reference), (backend, len(actual))
    for request, got, want in zip(requests, actual, reference):
        assert got == want, (backend, request, got[:120], want[:120])
    print(f'{backend}: {len(cases)-1} exact upstream pixel comparisons, one 77100-pixel ordered checksum, and {len(errors)} invalid-input cases PASS')
