"""Compare native resize decisions with pinned Pi's actual resize-core source."""
import argparse
import base64
import json
from pathlib import Path
import random
import re
import struct
import subprocess
import tempfile
import zlib
from upstream_pin import PIN

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', default='build/image-resize-policy')
p.add_argument('--photon', required=True)
args = p.parse_args()
photon = Path(args.photon).resolve()
assert json.loads((photon.parent/'package.json').read_text())['version'] == '0.3.4'


def source(name):
    return subprocess.check_output(['git', '-C', str(ROOT.parent/'pi-mono'), 'show',
                                    f'{PIN}:packages/coding-agent/src/utils/{name}'], text=True)


def png(w, h, seed):
    rng = random.Random(seed)
    rows = b''.join(b'\0' + rng.randbytes(w*4) for _ in range(h))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


cases = []
for w, h in [(1, 1), (1, 9), (11, 1), (7, 9), (19, 17), (64, 48)]:
    data = base64.b64encode(png(w, h, w*31+h)).decode()
    for options in [{}, {'maxWidth': 4}, {'maxHeight': 3}, {'maxWidth': 8, 'maxHeight': 5},
                    {'maxBytes': len(data)+1}, {'maxBytes': len(data)}, {'maxBytes': 4}]:
        cases.append({'data': data, 'mime': 'image/png', 'options': options})
data = base64.b64encode(png(64, 48, 98)).decode()
for limit in [6000, 4000, 2000, 1200, 900, 800]:
    for quality in [80, 40]:
        cases.append({'data': data, 'mime': 'image/png', 'options': {'maxBytes': limit, 'jpegQuality': quality}})


# Replay the original suite's exact image fixtures and options as well as the
# broader generated corpus above. Obtain fixtures from the pinned source.
upstream_tests = subprocess.check_output(['git', '-C', str(ROOT.parent/'pi-mono'), 'show',
    f'{PIN}:packages/coding-agent/test/image-processing.test.ts'], text=True)
original = dict(re.findall(r'const (TINY_PNG|TINY_JPEG|MEDIUM_PNG_100x100|LARGE_PNG_200x200)\s*=\s*"([^"]+)"', upstream_tests))
for name, mime, options in [
    ('TINY_PNG', 'image/png', {'maxWidth':100,'maxHeight':100,'maxBytes':1048576}),
    ('MEDIUM_PNG_100x100', 'image/png', {'maxWidth':50,'maxHeight':50,'maxBytes':1048576}),
    ('LARGE_PNG_200x200', 'image/png', {'maxWidth':2000,'maxHeight':2000,'maxBytes':len(original['LARGE_PNG_200x200'])*9//10}),
    ('LARGE_PNG_200x200', 'image/png', {'maxWidth':2000,'maxHeight':2000,'maxBytes':1}),
    ('TINY_JPEG', 'image/jpeg', {'maxWidth':100,'maxHeight':100,'maxBytes':1048576}),
]:
    cases.append({'data':original[name], 'mime':mime, 'options':options})


def command(case):
    opts = case['options']
    return ':'.join([str(opts.get(k, 'default')) for k in ['maxWidth', 'maxHeight', 'maxBytes', 'jpegQuality']]
                    + [case['mime'], case['data']])


def run_backend(backend, requests):
    prefix = ROOT/args.prefix
    cmd = ['bun', str(prefix)+'.js'] if backend == 'bun' else [str(prefix), '--threads', backend[-1]]
    output = []
    for offset in range(0, len(requests), 6):
        result = subprocess.run(cmd+requests[offset:offset+6], capture_output=True, text=True, check=True, timeout=120)
        output.extend(result.stdout.splitlines())
    assert len(output) == len(requests)
    return output


def parsed(value):
    if value == 'none':
        return None
    mime, ow, oh, w, h, changed, data = value.split(':')
    return {'mimeType': mime, 'originalWidth': int(ow), 'originalHeight': int(oh), 'width': int(w),
            'height': int(h), 'wasResized': changed == 'true', 'data': data}


with tempfile.TemporaryDirectory(prefix='image-resize-reference-') as folder:
    directory = Path(folder)
    exif = source('exif-orientation.ts')
    (directory/'exif-orientation.ts').write_text(exif)
    core = source('image-resize-core.ts').replace('import { loadPhoton } from "./photon.ts";',
                                               'const loadPhoton = async () => require('+json.dumps(str(photon))+');')
    (directory/'core.ts').write_text(core)
    (directory/'run.ts').write_text('''
import fs from 'node:fs';
import { resizeImageInProcess } from './core.ts';
const cases = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const c of cases) console.log(JSON.stringify(await resizeImageInProcess(Buffer.from(c.data,'base64'),c.mime,c.options)));
''')
    input_path = directory/'input.json'
    input_path.write_text(json.dumps(cases))
    reference = subprocess.run(['bun', str(directory/'run.ts'), str(input_path)], capture_output=True,
                               text=True, check=True, timeout=120)
    expected = [json.loads(line) for line in reference.stdout.splitlines()]
    assert len(expected) == len(cases)
    for backend in args.backends:
        actual = [parsed(line) for line in run_backend(backend, list(map(command, cases)))]
        pairs = []
        for i, (case, got, want) in enumerate(zip(cases, actual, expected)):
            assert (got is None) == (want is None), (backend, i, got, want)
            if got is None:
                continue
            fields = ['mimeType', 'originalWidth', 'originalHeight', 'width', 'height', 'wasResized']
            assert all(got[k] == want[k] for k in fields), (backend, i, {k:got[k] for k in fields}, {k:want[k] for k in fields})
            assert len(got['data']) < case['options'].get('maxBytes', 4718592), (backend, i)
            if not got['wasResized']:
                assert got['data'] == want['data'] == case['data'], (backend, i)
            else:
                if got['mimeType'] == 'image/jpeg':
                    assert got['data'] == want['data'], (backend, i, 'JPEG encoding/quality differs')
                pairs.extend([got['data'], want['data']])
        paths = []
        for i, data in enumerate(pairs):
            path = directory/f'{backend}-{i}.img'
            path.write_bytes(base64.b64decode(data, validate=True))
            paths.append(str(path))
        pixels = subprocess.run(['bun', str(ROOT/'tests/png_reference.cjs'), str(photon), *paths],
                                capture_output=True, text=True, check=True, timeout=120)
        images = [json.loads(line) for line in pixels.stdout.splitlines()]
        assert all(images[i] == images[i+1] for i in range(0, len(images), 2)), backend
        data = cases[0]["data"]
        invalid = [f'0:1:1000:80:image/png:{data}', f'1:0:1000:80:image/png:{data}',
                   f'1:1:0:80:image/png:{data}', f'1:1:1000:256:image/png:{data}',
                   'default:default:default:default:image/png:AA==']
        assert run_backend(backend, invalid) == ['none'] * len(invalid), backend
        print(f'{backend}: {len(cases)} pinned Pi resize decisions/pixels and {len(invalid)} strict-input cases PASS', flush=True)
