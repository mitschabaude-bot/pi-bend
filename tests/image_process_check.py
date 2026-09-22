"""Actual Pi image-process comparisons and public read-tool image integration."""
import argparse
import base64
import json
import re
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
PIN = '46c9de402bddf46b03c3b9f46487b777aaa41861'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--photon', required=True)
p.add_argument('--prefix', default='build/image-process')
p.add_argument('--read-prefix', default='build/read-public-images')
a = p.parse_args()
photon = Path(a.photon).resolve()
assert json.loads((photon.parent/'package.json').read_text())['version'] == '0.3.4'


def source(name):
    return subprocess.check_output(['git', '-C', str(ROOT.parent/'pi-mono'), 'show',
                                    f'{PIN}:packages/coding-agent/src/utils/{name}'], text=True)


def png(w, h):
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    rows = b''.join(b'\0'+bytes((x*7+y*11) % 256 for x in range(w*4)) for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))+chunk(b'IDAT', zlib.compress(rows))+chunk(b'IEND', b'')


gif = b'GIF89a'+struct.pack('<HHBBB', 1, 1, 128, 0, 0)+bytes([20,40,60,255,255,255,44])+struct.pack('<HHHHB',0,0,1,1,0)+bytes([2,2,68,1,0,59])
bmp = b'BM'+struct.pack('<IHHI',58,0,0,54)+struct.pack('<IiiHHIIiiII',40,1,1,1,24,0,4,0,0,0,0)+bytes([0,0,255,0])
files = [('small.png', png(7,9), 'image/png'), ('large.png', png(2010,3), 'image/png'),
         ('tiny.gif', gif, 'image/gif'), ('opaque-image', bmp, 'image/bmp'), ('broken.gif', b'GIF89a', 'image/gif')]
upstream_tests = subprocess.check_output(['git','-C',str(ROOT.parent/'pi-mono'),'show',
    f'{PIN}:packages/coding-agent/test/image-processing.test.ts'],text=True)
jpeg = base64.b64decode(re.search(r'const TINY_JPEG_2X1\s*=\s*"([^"]+)"',upstream_tests)[1])
def app1(payload): return b'\xff\xe1'+struct.pack('>H',len(payload)+2)+payload
xmp = app1(b'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x="adobe:ns:meta/"/>')
exif = app1(b'Exif\0\0'+bytes.fromhex('49492a0008000000010012010300010000000600000000000000'))
files += [('tiny.jpg',jpeg,'image/jpeg'),('oriented.jpg',jpeg[:2]+xmp+exif+jpeg[2:],'image/jpeg')]
cases = []
for _, data, mime in files:
    for resize in [True, False]:
        cases.append({'data':base64.b64encode(data).decode(), 'mime':mime, 'options':{'autoResizeImages':resize}})
for mime in [' IMAGE/PNG ; charset=binary ', 'image/jpg', 'image/jpeg', 'image/webp', 'IMAGE/GIF', 'unknown', '']:
    for resize in [True, False]:
        cases.append({'data':base64.b64encode(files[0][1]).decode(), 'mime':mime, 'options':{'autoResizeImages':resize}})
cases += [{'data':base64.b64encode(files[0][1]).decode(), 'mime':'image/png', 'options':{'resizeOptions':opts}}
          for opts in [{'maxWidth':4}, {'maxHeight':3}, {'maxBytes':4}]]
cases.append({'data':base64.b64encode(b'garbage').decode(), 'mime':'image/bmp', 'options':{}})


def command(case):
    options = case['options']
    limits = options.get('resizeOptions', {})
    return ':'.join([str(options.get('autoResizeImages',True)).lower()]
                    + [str(limits.get(key,'default')) for key in ['maxWidth','maxHeight','maxBytes','jpegQuality']]
                    + [case['mime'],case['data']])


def runner(backend, prefix):
    return ['bun',str(ROOT/prefix)+'.js'] if backend=='bun' else [str(ROOT/prefix),'--threads',backend[-1]]


def execute(command, requests):
    output = []
    for start in range(0,len(requests),8):
        run = subprocess.run(command+requests[start:start+8], capture_output=True,text=True,check=True,timeout=180)
        output.extend(json.loads(line) for line in run.stdout.splitlines())
    assert len(output)==len(requests)
    return output


with tempfile.TemporaryDirectory(prefix='image-process-') as folder:
    directory = Path(folder)
    loader = 'const loadPhoton = async () => require('+json.dumps(str(photon))+');'
    for name in ['exif-orientation.ts','image-resize-core.ts','image-convert.ts','image-process.ts']:
        text = source(name).replace('import { loadPhoton } from "./photon.ts";',loader)
        (directory/name).write_text(text)
    wrapper = source('image-resize.ts')
    (directory/'image-resize.ts').write_text('export { resizeImageInProcess as resizeImage } from "./image-resize-core.ts";\n'
                                          +wrapper[wrapper.index('export function formatDimensionNote'):])
    oracle = directory/'run.ts'
    oracle.write_text('''
import fs from 'node:fs';
import { processImage } from './image-process.ts';
import { formatDimensionNote } from './image-resize.ts';
for (const c of JSON.parse(fs.readFileSync(process.argv[2], 'utf8')))
  console.log(JSON.stringify(c.note ? formatDimensionNote({...c.note,wasResized:true}) : await processImage(Buffer.from(c.data,'base64'),c.mime,c.options)));
''')
    notes = [{'originalWidth':ow,'originalHeight':9,'width':w,'height':3} for ow,w in [(201,200),(535,200),(1,1),(8,3),(2147483648,1)]]
    requests = cases+[{'note':note} for note in notes]
    path = directory/'cases.json'; path.write_text(json.dumps(requests))
    reference = subprocess.run(['bun',str(oracle),str(path)],capture_output=True,text=True,check=True,timeout=180)
    expected = [json.loads(line) for line in reference.stdout.splitlines()]
    assert len(expected)==len(requests)
    for backend in a.backends:
        actual = execute(runner(backend,a.prefix),list(map(command,cases))+[f'note:{n["originalWidth"]}:9:{n["width"]}:3' for n in notes])
        pairs=[]
        for i,(got,want) in enumerate(zip(actual,expected)):
            if i>=len(cases) or not want['ok']:
                assert got==want,(backend,i,got,want)
                continue
            assert got['ok'] and got['mimeType']==want['mimeType'] and got['hints']==want['hints'],(backend,i,got,want)
            if cases[i]['mime'] == 'image/bmp':
                assert base64.b64decode(got['data']).startswith(b'\x89PNG'), (backend, i, 'BMP conversion must emit PNG magic')
            if got['data']!=want['data']:
                pairs.extend([got['data'],want['data']])
        pixel_paths=[]
        for i,data in enumerate(pairs):
            path=directory/f'{backend}-pixels-{i}'; path.write_bytes(base64.b64decode(data)); pixel_paths.append(str(path))
        if pixel_paths:
            decoded=subprocess.run(['bun',str(ROOT/'tests/png_reference.cjs'),str(photon),*pixel_paths],capture_output=True,text=True,check=True,timeout=90)
            pixels=[json.loads(line) for line in decoded.stdout.splitlines()]
            assert all(pixels[i]==pixels[i+1] for i in range(0,len(pixels),2)),backend
        # Run the public read AgentTool with real files and its default image
        # processor. The pure results above also check the upstream process API.
        for name,data,_ in files: (directory/name).write_bytes(data)
        for resize,mode in [(True,'default'),(False,'native-noresize')]:
            tool=execute(runner(backend,a.read_prefix)+[str(directory),str(directory),mode],[json.dumps({'path':name}) for name,_,_ in files])
            for i,(result,(_,_,mime)) in enumerate(zip(tool,files)):
                processed=actual[i*2+(0 if resize else 1)]
                if processed['ok']:
                    text='Read image file ['+processed['mimeType']+']'+('' if not processed['hints'] else '\n'+'\n'.join(processed['hints']))
                    content=[['text',text],['image',processed['data'],processed['mimeType']]]
                else: content=[['text','Read image file ['+mime+']\n'+processed['message']]]
                assert result=={'content':content,'truncated':False},(backend,i,mode,result,content)
        print(f'{backend}: {len(cases)} Pi image-process comparisons, {len(notes)} dimension notes, and {2*len(files)} public read image calls PASS',flush=True)
