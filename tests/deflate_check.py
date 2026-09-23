#!/usr/bin/env python3
"""Independent zlib oracle plus explicit RFC framing/tree/budget boundaries."""
import argparse
import os
import random
import subprocess
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
parser.add_argument('--prefix', default='build/deflate')
args = parser.parse_args()
rng = random.Random(1951)
cases = []


def add(label, mode, compressed, expected, limit=None):
    if isinstance(expected, bytes):
        assert zlib.decompress(compressed, -15 if mode == 'raw' else 15) == expected, label
        result = 'ok ' + ','.join(map(str, expected))
        limit = len(expected) if limit is None else limit
    else:
        result = 'error ' + expected
        limit = 200000 if limit is None else limit
    cases.append((label, f'{mode}:{limit}:' + ','.join(map(str, compressed)), result))


payloads = [b'', b'x', b'ab', bytes(range(256)), b'a'*70000,
            b'abc'*24000, rng.randbytes(20000)*4, b'\0'*1024 + b'hello'*10000]
payloads += [rng.randbytes(rng.randrange(2000)) for _ in range(8)]
for i, data in enumerate(payloads):
    for strategy in [zlib.Z_DEFAULT_STRATEGY, zlib.Z_FIXED, zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE]:
        # Keep each argument below Linux's per-string exec limit.
        if len(data) > 30000 and strategy in [zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE] and len(set(data)) > 3:
            continue
        for mode, bits in [('zlib', 15), ('raw', -15)]:
            c = zlib.compressobj(6, zlib.DEFLATED, bits, 8, strategy)
            packed = c.compress(data) + c.flush()
            add(f'payload {i} strategy {strategy} {mode}', mode, packed, data)
            if data:
                add('budget one below', mode, packed, 'limit', len(data)-1)
for mode, bits in [('zlib', 15), ('raw', -15)]:
    data = rng.randbytes(8000)
    c = zlib.compressobj(0, zlib.DEFLATED, bits)
    add('stored block', mode, c.compress(data)+c.flush(), data)
    c = zlib.compressobj(6, zlib.DEFLATED, bits)
    packed = c.compress(data)+c.flush(zlib.Z_SYNC_FLUSH)
    packed += c.compress(data)+c.flush(zlib.Z_FULL_FLUSH)
    packed += c.compress(b'a'*40000)+c.flush()
    add('cross-block history and empty stored sync', mode, packed, data+data+b'a'*40000)


class Bits:
    def __init__(self):
        self.bits = []

    def put(self, value, count):
        self.bits.extend((value >> i) & 1 for i in range(count))
        return self

    def code(self, lengths, symbol):
        counts = [lengths.count(i) for i in range(16)]
        counts[0] = 0
        code = 0
        for length in range(1, lengths[symbol]+1):
            code = (code+counts[length-1])*2
        code += sum(x == lengths[symbol] for x in lengths[:symbol])
        self.bits.extend((code >> i) & 1 for i in reversed(range(lengths[symbol])))
        return self

    def bytes(self, padding=0):
        bits = self.bits + [padding] * ((-len(self.bits)) % 8)
        return bytes(sum(bits[i+j] << j for j in range(8)) for i in range(0, len(bits), 8))


ORDER = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]


def dynamic(literal, distance, encoded_lengths=None):
    b = Bits().put(5, 3).put(len(literal)-257, 5).put(len(distance)-1, 5).put(15, 4)
    lengths = [4]*16+[0]*3 if encoded_lengths is None else [2,2]+[0]*14+[2,3,3]
    for i in ORDER:
        b.put(lengths[i], 3)
    if encoded_lengths is None:
        for value in literal+distance:
            b.code(lengths, value)
    else:
        for symbol, extra, width in encoded_lengths:
            b.code(lengths, symbol).put(extra, width)
    return b


literal = [0]*256+[1]
b = dynamic(literal, [0]).code(literal, 256)
add('single EOB, empty distance tree, nonzero padding', 'raw', b.bytes(1), b'')
add('single EOB and single distance code', 'raw', dynamic(literal,[1]).code(literal,256).bytes(), b'')
# Zero runs 138+118, then EOB length 1 and absent distance length 0.
b = dynamic(literal,[0],[(18,127,7),(18,107,7),(1,0,0),(0,0,0)]).code(literal,256)
add('repeat 18 zeros', 'raw', b.bytes(), b'')
# Repeat 16 previous zero, and repeat 17, in addition to repeat 18.
b = dynamic(literal,[0],[(0,0,0),(16,0,2),(17,0,3),(18,127,7),(18,100,7),(1,0,0),(0,0,0)]).code(literal,256)
add('all three repeat forms', 'raw', b.bytes(), b'')
literal = [0]*258
literal[65],literal[256],literal[257] = 1,2,2
b = dynamic(literal,[1]).code(literal,65).code(literal,257).code([1],0).code(literal,256)
add('dynamic single distance overlapping length 3', 'raw', b.bytes(), b'AAAA')
# Fixed tree invalid/reserved codes and distance-before-output.
fixed = [8]*144+[9]*112+[7]*24+[8]*8
for label, build, expected in [
    ('reserved literal', Bits().put(3,3).code(fixed,286), 'reserved'),
    ('reserved distance', Bits().put(3,3).code(fixed,257).code([5]*32,30), 'reserved'),
    ('distance without history', Bits().put(3,3).code(fixed,257).code([5]*32,0), 'distance')]:
    add(label,'raw',build.bytes(),expected)
for label, literal, distance, expected in [
    ('oversubscribed literal', [1]*257,[0],'oversubscribed'),
    ('incomplete literal', [0]*256+[2],[0],'incomplete'),
    ('missing EOB', [1]+[0]*256,[0],'end-code'),
    ('oversubscribed distance', [0]*256+[1],[1,1,1],'oversubscribed'),
    ('incomplete distance', [0]*256+[1],[2],'incomplete')]:
    add(label,'raw',dynamic(literal,distance).bytes(),expected)
add('repeat 16 before prior length','raw',dynamic([0]*256+[1],[0],[(16,0,2)]).bytes(),'repeat')
add('repeat exceeds declared lengths','raw',dynamic([0]*256+[1],[0],[(18,127,7),(18,127,7)]).bytes(),'repeat')
add('reserved block','raw',b'\x07','block')
add('stored complement','raw',b'\x01\x01\x00\xff\xffx','stored-length')
add('invalid octet','raw',[300],'byte')
for data in [b'', b'abc', bytes(range(256))*4]:
    packed = zlib.compress(data)
    for cut in range(len(packed)):
        add('truncated zlib','zlib',packed[:cut],'truncated')
    add('trailing zlib','zlib',packed+b'\0','trailing')
    add('checksum mismatch','zlib',packed[:-1]+bytes([packed[-1]^1]),'checksum')
    add('trailing raw','raw',packed[2:-4]+b'\0','trailing')
add('wrong method','zlib',b'\x79\x18','header')
add('oversized window','zlib',b'\x88\x1c','header')
add('header FCHECK','zlib',b'\x78\x00','header-check')
add('preset dictionary','zlib',b'\x78\x20','dictionary')

# A complete comb tree exercises every code length, including the 10–15-bit fallback.
literal = [0]*257
for i in range(14):
    literal[i] = i+1
literal[14] = literal[256] = 15
b = dynamic(literal,[0])
for value in range(15):
    b.code(literal,value)
b.code(literal,256)
add('all Huffman lengths through 15', 'raw', b.bytes(1), bytes(range(15)))
# Stored history followed by a fixed match at the exact 32768-byte distance.
b = Bits().put(3,3).code(fixed,257).code([5]*32,29).put(8191,13).code(fixed,256)
packed = b'\x00\x00\x80\xff\x7f' + bytes(32768) + b.bytes()
add('maximum distance after stored block', 'raw', packed, bytes(32771))
# The advertised zlib window constrains otherwise valid DEFLATE backreferences.
b = Bits().put(3,3)
for i in range(257):
    b.code(fixed,65)
b.code(fixed,257).code([5]*32,16).put(0,7).code(fixed,256)
raw = b.bytes()
add('distance 257 raw', 'raw', raw, b'A'*260)
add('distance exceeds advertised 256-byte window', 'zlib', b'\x08\x1d'+raw+zlib.adler32(b'A'*260).to_bytes(4,'big'), 'distance')

for backend in args.backends:
    command = ['bun', str(ROOT / (args.prefix+'.js'))] if backend == 'bun' else [str(ROOT/args.prefix), '--threads', backend.split('-')[1]]
    count = 0
    for start in range(0,len(cases),8):
        batch = cases[start:start+8]
        result = subprocess.run(command+[x[1] for x in batch], text=True, capture_output=True, timeout=60)
        assert result.returncode == 0, (backend,result.returncode,result.stderr)
        actual = result.stdout.splitlines()
        assert len(actual) == len(batch), (backend,len(actual),len(batch),result.stderr)
        for got, (label, request, want) in zip(actual,batch):
            assert got == want, (backend,label,request[:150],got[:150],want[:150])
        count += len(batch)
    print(f'{backend}: {count} DEFLATE/zlib cases pass')
