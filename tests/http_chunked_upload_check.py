"""Buffered chunk framing and exact hexadecimal sizes, including limb carries."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
args, expected = [], []
for bits in [0, 1, 4, 8, 12, 16, 32, 48, 64, 128, 256, 512]:
    for value in [max(0, (1 << bits) - 1), 1 << bits, (1 << bits) + 1]:
        args.append('h' + str(value))
        expected.append(format(value, 'x'))
for size in [0, 1, 15, 16, 17, 255, 256, 257, 4095, 4096, 65535, 65536, 65537]:
    args.append('z' + str(size))
    wire = (format(size, 'x').encode() + b'\r\n' + bytes(size) + b'\r\n' if size else b'') + b'0\r\n\r\n'
    expected.append(','.join(map(str, wire)))
for payload in [bytes(range(256)), b'\x00\xff\r\n']:
    args.append('b' + ','.join(map(str, payload)))
    wire = format(len(payload), 'x').encode() + b'\r\n' + payload + b'\r\n0\r\n\r\n'
    expected.append(','.join(map(str, wire)))
args.append('b256')
expected.append('error')
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-chunked-upload.bend', 'build/http-chunked-upload'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(args), 8):
        result = subprocess.run([str(ROOT / 'build/http-chunked-upload'), '--threads', threads, *args[start:start + 8]], cwd=ROOT, text=True, capture_output=True, check=True, timeout=30)
        for i, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start + 8], strict=True)):
            assert got == want, (threads, args[start + i], got[:150], want[:150])
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(args)} hexadecimal/chunked upload cases PASS')
