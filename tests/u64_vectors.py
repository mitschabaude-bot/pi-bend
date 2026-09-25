"""Generate independent integer-oracle vectors; compiled code is pure Bend.

No Python or C arithmetic is called by the implementation or native tests.
Operation order matches packages/runtime/test/u64-support.bend.
"""
import pathlib
import random
import subprocess

mask = (1 << 64) - 1
edges = [0, 1, 2, 0xFFFF, 0x10000, 0xFFFFFFFF, 1 << 32, (1 << 32) + 1,
         (1 << 63) - 1, 1 << 63, mask - 1, mask]
shifts = [0, 1, 15, 16, 31, 32, 33, 47, 48, 63, 64, 65, 127, 128]
rng = random.Random(6400851)
vectors = [(a, b, shifts[(i + j) % len(shifts)]) for i, a in enumerate(edges) for j, b in enumerate(edges)]
vectors += [(rng.getrandbits(64), rng.getrandbits(64), rng.randrange(130)) for _ in range(128)]

def word(n):
    n &= mask
    return f"W.U64{{{n >> 32}, {n & 0xFFFFFFFF}}}"

source = ['import Base', 'import ../packages/runtime/src/u64.bend as W',
          'import ../packages/runtime/test/u64-support.bend as H']
for index, (a, b, shift) in enumerate(vectors):
    n = shift % 64
    expected = [a+b, a-b, a*b, a&b, a|b, a^b, ~a,
                a << shift, a >> shift, (a << n) | (a >> (64-n)),
                (a >> n) | (a << (64-n))]
    q, r = divmod(a, b) if b else (0, 0)
    ordering = 0 if a < b else 1 if a == b else 2
    values = ' <> '.join(map(word, expected)) + ' <> Nil{}'
    product = a * b
    jam = (product >> shift) | int((product & ((1 << shift)-1)) != 0)
    source.append(f'def case{index}() -> H.Case:\n  H.Case{{"vector {index}", {word(a)}, {word(b)}, {shift}n, {values}, {word(q)}, {word(r)}, {ordering}, {word(product >> 64)}, {word(product)}, {word(jam >> 64)}, {word(jam)}}}')
source.append('def main() -> IO(Unit):\n  H.checkAll(' + ' <> '.join(f'case{i}()' for i in range(len(vectors))) + ' <> Nil{})')
pathlib.Path('build').mkdir(exist_ok=True)
pathlib.Path('build/u64-vectors.bend').write_text('\n\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'build/u64-vectors.bend', 'build/test-u64'], check=True)
subprocess.run(['build/test-u64', '--threads', '1'], check=True, timeout=60)
print(f'u64/u128: {len(vectors)} vectors, arithmetic/bitwise/shifts/rotations/division/comparison/full products/jam passed')
