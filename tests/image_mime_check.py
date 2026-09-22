"""Pure image recognition against pinned Pi mime.ts; no image decoding or file IO."""
import argparse
import json
import os
from pathlib import Path
import random
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PNG = b'\x89PNG\r\n\x1a\n'


def chunk(kind, data=b'', declared=None):
    return struct.pack('>I', len(data) if declared is None else declared) + kind + data + b'\0'*4


def bmp(header=40, planes=1, depth=24, size=58, pixels=54):
    data = bytearray(58)
    data[:2] = b'BM'
    struct.pack_into('<I', data, 2, size)
    struct.pack_into('<II', data, 10, pixels, header)
    struct.pack_into('<HH', data, 22 if header == 12 else 26, planes, depth)
    return bytes(data)


def corpus():
    cases = [b'', b'not an image', b'GIF', b'GIF00?', b'RIFF\0\0\0\0WEBP', b'RIFFxxxxWAVE']
    cases += [b'\xff\xd8\xff'] + [b'\xff\xd8\xff'+bytes([n]) for n in range(256)]
    seeds = [PNG + chunk(b'IHDR', b'\0'*13), b'GIF89a', b'RIFF1234WEBP', bmp()]
    for value in seeds:
        cases += [value[:length] for length in range(len(value)+1)]
        cases += [value[:i]+bytes([value[i]^1])+value[i+1:] for i in range(min(16, len(value)))]
    ihdr = chunk(b'IHDR', b'\0'*13)
    for middle in [b'', chunk(b'tEXt'), chunk(b'tEXt', b'abc'), chunk(b'tEXt', b'acTLIDAT')]:
        for tail in [chunk(b'acTL'), chunk(b'IDAT'), chunk(b'acTL')+chunk(b'IDAT'), chunk(b'IDAT')+chunk(b'acTL')]:
            value = PNG+ihdr+middle+tail
            cases += [value[:n] for n in range(len(value)+1)]
    for length in [0, 1, 12, 13, 14, 0x7fffffff, 0xffffffff]:
        cases.append(PNG+chunk(b'IHDR', b'\0'*13, length)+chunk(b'acTL'))
        cases.append(PNG+ihdr+chunk(b'tEXt', b'', length)+chunk(b'acTL'))
    for header in [0, 11, 12, 13, 39, 40, 41, 64, 108, 124, 125, 0xffffffff]:
        for planes in [0, 1, 2]:
            for depth in [0, 1, 2, 4, 8, 16, 24, 32, 64, 256]:
                cases.append(bmp(header, planes, depth, 0, min(0xffffffff, header+14)))
    for size in [0, 1, 25, 26, 27, 53, 54, 58, 0xffffffff]:
        for pixels in [0, 13, 25, 26, 53, 54, 57, 58, 0xffffffff]:
            cases.append(bmp(size=size, pixels=pixels))
    rng = random.Random(20260922)
    for _ in range(500):
        chunks = []
        for _ in range(rng.randrange(8)):
            kind = rng.choice([b'tEXt', b'acTL', b'IDAT', b'IEND', b'IHDR'])
            payload = rng.randbytes(rng.randrange(24))
            chunks.append(chunk(kind, payload, rng.choice([None, None, None, 0, 0xffffffff])))
        value = PNG + ihdr + b''.join(chunks)
        cases.append(value[:rng.randrange(len(value)+1)])
    # Preserve order while discarding duplicate coverage from prefix truncations.
    return list(dict.fromkeys(cases))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=ROOT.parent/'pi-mono')
    parser.add_argument('--bend', type=Path)
    parser.add_argument('--no-build', action='store_true')
    args = parser.parse_args()
    prefix = ROOT/'build/image-mime'
    prefix.parent.mkdir(exist_ok=True)
    compiler = args.bend or Path(os.environ.get('BEND', str(ROOT/'build/bend-native-toolchain/bend2/main.ts')))
    if not args.no_build:
        subprocess.run([str(compiler), 'tests/image-mime.bend', '-o', str(prefix)+'.js'], cwd=ROOT, check=True)
        subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/image-mime.bend', str(prefix)], cwd=ROOT,
                       env=dict(os.environ, BEND=str(compiler)), check=True)
    cases = corpus()
    inputs = ROOT/'build/image-mime-cases.json'
    inputs.write_text(json.dumps([case.hex() for case in cases]))
    source = (args.reference/'packages/coding-agent/test/image-process.test.ts').read_text()
    start = source.index('function createTinyBmp1x1Red24bpp')
    end = source.index('\nfunction ', start+10)
    oracle = ROOT/'build/image-mime-oracle.ts'
    oracle.write_text('import { detectSupportedImageMimeType as detect } from '+
                      json.dumps(str((args.reference/'packages/coding-agent/src/utils/mime.ts').resolve()))+';\n'+
                      source[start:end]+'''
const inputs = await Bun.file(process.argv[2]).json();
const tiny = createTinyBmp1x1Red24bpp();
console.log(JSON.stringify({results:inputs.map(hex=>detect(Buffer.from(hex,'hex'))),tiny:tiny.toString('hex'),tinyMime:detect(tiny)}));
''')
    reference = json.loads(subprocess.check_output(['bun', str(oracle), str(inputs)], text=True))
    assert reference['tinyMime'] == 'image/bmp'
    cases.append(bytes.fromhex(reference['tiny']))
    expected = [value or 'null' for value in reference['results']] + ['image/bmp']
    for backend, command in [('bun', ['bun', str(prefix)+'.js']),
                             ('native-1', [str(prefix), '--threads', '1']),
                             ('native-4', [str(prefix), '--threads', '4'])]:
        for start in range(0, len(cases), 100):
            actual = subprocess.check_output(command+[case.hex() for case in cases[start:start+100]], text=True, timeout=30).splitlines()
            assert actual == expected[start:start+100], (backend, start, actual, expected[start:start+100])
        actual = subprocess.check_output(command+['long'], text=True, timeout=30).splitlines()
        assert actual == ['null', 'image/png', 'image/png', 'null', 'null'], (backend, actual)
        print(f'{backend}: {len(cases)} pinned-reference comparisons, upstream BMP magic assertion, 20,000-chunk PNG scans and invalid-byte rejection PASS', flush=True)


if __name__ == '__main__':
    main()
