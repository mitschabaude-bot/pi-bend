"""Native image conversion: decoded pixels, MIME dispatch and budgets."""
import argparse
import base64
import json
import re
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib
from upstream_pin import PIN, UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', default='build/image-convert')
p.add_argument('--photon', required=True)
args = p.parse_args()
photon = Path(args.photon).resolve()
assert json.loads((photon.parent / 'package.json').read_text())['version'] == '0.3.4'


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def png(w, h, rgba):
    rows = b''.join(b'\0' + rgba[y*w*4:(y+1)*w*4] for y in range(h))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def bmp(w, h, rgba, top_down):
    rows = []
    for y in (range(h) if top_down else reversed(range(h))):
        row = b''.join(bytes((rgba[i+2], rgba[i+1], rgba[i])) for i in range(y*w*4, (y+1)*w*4, 4))
        rows.append(row + bytes((-len(row)) % 4))
    data = b''.join(rows)
    return (b'BM' + struct.pack('<IHHI', 54+len(data), 0, 0, 54)
            + struct.pack('<IiiHHIIiiII', 40, w, -h if top_down else h, 1, 24, 0, len(data), 0, 0, 0, 0) + data)


def b64(data):
    return base64.b64encode(data).decode()


def reference(images, directory, label):
    paths = []
    for i, image in enumerate(images):
        path = Path(directory) / f'{label}-{i}'
        path.write_bytes(image)
        paths.append(str(path))
    run = subprocess.run(['bun', str(ROOT/'tests/png_reference.cjs'), str(photon), *paths],
                         capture_output=True, text=True, check=True, timeout=90)
    return [json.loads(line) for line in run.stdout.splitlines()]


fixtures = []
for w, h in [(1, 1), (1, 7), (9, 1), (2, 3), (7, 9), (16, 13)]:
    rgba = bytes((i*73 + i//4*29) % 256 for i in range(w*h*4))
    for kind, image in [('png', png(w, h, rgba)), ('bmp', bmp(w, h, rgba, False)), ('bmp', bmp(w, h, rgba, True))]:
        fixtures.append((w, h, kind, image))

# Exercise GIF conversion, including its transparent palette entry. Broader
# LZW/frame/interlace behavior is covered by the standalone GIF oracle suite.
for transparent in [False, True]:
    image = (b'GIF89a' + struct.pack('<HHBBB', 1, 1, 128, 0, 0)
             + bytes([20, 40, 60, 255, 255, 255])
             + (bytes([33, 249, 4, 1, 0, 0, 0, 0]) if transparent else b'')
             + b',' + struct.pack('<HHHHB', 0, 0, 1, 1, 0)
             + bytes([2, 2, 68, 1, 0, 59]))
    fixtures.append((1, 1, 'gif', image))


upstream_tests = subprocess.check_output(['git','-C',str(UPSTREAM),'show',
    f'{PIN}:packages/coding-agent/test/image-processing.test.ts'],text=True)
original = dict(re.findall(r'const (TINY_PNG|TINY_JPEG|TINY_JPEG_2X1)\s*=\s*"([^"]+)"',upstream_tests))
fixtures += [(2,2,'png',base64.b64decode(original['TINY_PNG'])),
             (2,2,'jpeg',base64.b64decode(original['TINY_JPEG']))]
def app1(payload): return b'\xff\xe1'+struct.pack('>H',len(payload)+2)+payload
jpeg = base64.b64decode(original['TINY_JPEG_2X1'])
xmp = app1(b'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x="adobe:ns:meta/"/>')
exif = app1(b'Exif\0\0'+bytes.fromhex('49492a0008000000010012010300010000000600000000000000'))
oriented_jpeg = jpeg[:2]+xmp+exif+jpeg[2:]


def run_backend(backend, requests):
    prefix = ROOT / args.prefix
    command = ['bun', str(prefix)+'.js'] if backend == 'bun' else [str(prefix), '--threads', backend[-1]]
    output = []
    for start in range(0, len(requests), 12):
        run = subprocess.run(command + requests[start:start+12], capture_output=True, text=True, check=True, timeout=90)
        output.extend(run.stdout.splitlines())
    assert len(output) == len(requests), (backend, len(output), len(requests))
    return output


with tempfile.TemporaryDirectory(prefix='image-convert-') as directory:
    expected = reference([image for _, _, _, image in fixtures], directory, 'source')
    requests, expected_images = [], []
    for (_, _, kind, image), pixels in zip(fixtures, expected):
        for mime in ['image/'+kind, 'application/octet-stream', 'IMAGE/PNG']:
            requests.append(f'convert:{mime}:{b64(image)}')
            expected_images.append(pixels)
        requests.append(f'bounded:100000:1000000:{b64(image)}')
        expected_images.append(pixels)
    for backend in args.backends:
        actual = run_backend(backend, requests)
        images = []
        for result in actual:
            assert result.startswith('image/png:'), (backend, result)
            images.append(base64.b64decode(result.removeprefix('image/png:'), validate=True))
        assert reference(images, directory, backend) == expected_images, backend
        bounds, want = [], []
        for i, (w, h, _, image) in enumerate(fixtures):
            encoded = actual[i*4+3]
            length = len(images[i*4+3])
            for pixels, limit, output in [(w*h, length, encoded), (w*h, length-1, 'none'), (w*h-1, length, 'none')]:
                bounds.append(f'bounded:{pixels}:{limit}:{b64(image)}')
                want.append(output)
        for data, mime, output in [('', 'image/png', 'image/png:'), ('not-base64', 'image/png', 'image/png:not-base64'),
                                   ('not-base64', 'image/bmp', 'none'), ('AA==', 'image/bmp', 'none'),
                                   (b64(b'BM'), 'image/bmp', 'none'), (b64(b'\x89PNG'), 'other', 'none')]:
            bounds.append(f'convert:{mime}:{data}')
            want.append(output)
        assert run_backend(backend, bounds) == want, backend
        original_results = run_backend(backend, [f"convert:image/png:{original['TINY_PNG']}",
            f"convert:image/jpeg:{original['TINY_JPEG']}", f"convert:image/jpeg:{b64(oriented_jpeg)}"])
        assert original_results[0] == 'image/png:'+original['TINY_PNG'], backend
        for output, dimensions in zip(original_results[1:], [(2,2),(1,2)]):
            assert output.startswith('image/png:'), (backend,output)
            decoded = base64.b64decode(output.removeprefix('image/png:'),validate=True)
            assert decoded.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack('>II',decoded[16:24])==dimensions,backend
        print(f'{backend}: {len(actual)} conversion pixel comparisons, {len(bounds)} budget/pass-through/error checks, and 3 original conversion cases PASS', flush=True)
