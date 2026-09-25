#!/usr/bin/env python3
"""tool-result-images.test.ts: every upstream case against the native normalizeToolResultImages.

Runs natively by default: on the Bun lane the 2400x4800 fixtures overflow the
generated JavaScript's stack while decoding (docs/bend-issues.md BEND-019);
`bun` still runs when named.
"""
import argparse, base64, json, struct, subprocess, zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TINY_PNG_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))

def create_png(width, height):
    """An 8-bit grayscale PNG of arbitrary dimensions, as upstream's createPng."""
    raw = b''.join(b'\0' + bytes([row % 256]) * width for row in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

def png_dimensions(data):
    raw = base64.b64decode(data)
    return struct.unpack('>II', raw[16:24])

def tiny_bmp():
    buffer = bytearray(58)
    buffer[0:2] = b'BM'
    struct.pack_into('<I', buffer, 2, 58); struct.pack_into('<I', buffer, 10, 54); struct.pack_into('<I', buffer, 14, 40)
    struct.pack_into('<i', buffer, 18, 1); struct.pack_into('<i', buffer, 22, 1); struct.pack_into('<H', buffer, 26, 1)
    struct.pack_into('<H', buffer, 28, 24); struct.pack_into('<I', buffer, 34, 4); buffer[56] = 0xff
    return bytes(buffer)

def image(data, mime): return {'type': 'image', 'data': base64.b64encode(data).decode(), 'mimeType': mime}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prefix', default='build/tool-result-images')
    parser.add_argument('backends', nargs='*')
    args = parser.parse_args()
    for backend in args.backends or ['native-1', 'native-4']:
        command = ['bun', str(ROOT / (args.prefix + '.js'))] if backend == 'bun' else [str(ROOT / args.prefix), '--threads', backend[-1], '--']
        def run(content, mode='default'):
            result = subprocess.run(command + [mode, json.dumps(content)], capture_output=True, text=True, timeout=600)
            assert result.returncode == 0, (backend, result.stderr[-2000:])
            return json.loads(result.stdout)
        # returns the original array when there are no image blocks
        assert run([{'type': 'text', 'text': 'no images here'}]) == {'unchanged': True}
        # returns the original array when images are already within limits
        assert run([{'type': 'text', 'text': 'screenshot'}, {'type': 'image', 'data': TINY_PNG_BASE64, 'mimeType': 'image/png'}]) == {'unchanged': True}
        # resizes oversized images and reports the original dimensions
        normalized = run([image(create_png(2400, 4800), 'image/png')])['content']
        assert len(normalized) == 2 and normalized[0]['type'] == 'image', normalized[:1]
        width, height = png_dimensions(normalized[0]['data'])
        assert width <= 2000 and height <= 2000, (width, height)
        assert normalized[1]['type'] == 'text' and 'original 2400x4800' in normalized[1]['text'], normalized[1]
        # leaves oversized images alone when auto-resize is disabled
        assert run([image(create_png(2400, 4800), 'image/png')], 'false') == {'unchanged': True}
        # converts unsupported image formats even when auto-resize is disabled
        converted = run([image(tiny_bmp(), 'image/bmp')], 'false')['content']
        assert converted[0]['type'] == 'image' and converted[0]['mimeType'] == 'image/png', converted
        assert converted[1] == {'type': 'text', 'text': '[Image converted from image/bmp to image/png.]'}, converted[1]
        # keeps undecodable images instead of dropping tool output
        assert run([{'type': 'image', 'data': 'bm90LWFuLWltYWdl', 'mimeType': 'image/png'}]) == {'unchanged': True}
        # preserves surrounding text blocks and their order
        ordered = run([{'type': 'text', 'text': 'before'}, image(create_png(2400, 100), 'image/png'), {'type': 'text', 'text': 'after'}])['content']
        assert [block['type'] for block in ordered] == ['text', 'image', 'text', 'text'], ordered
        assert ordered[0] == {'type': 'text', 'text': 'before'} and ordered[3] == {'type': 'text', 'text': 'after'}
        print(f'{backend}: tool-result-images 7 upstream cases PASS', flush=True)

if __name__ == '__main__':
    main()
