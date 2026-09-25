"""Independent IEEE-754 oracle for pure Bend binary64 arithmetic."""
import math
import pathlib
import random
import struct
import subprocess

def bits(number):
    return struct.unpack('>Q', struct.pack('>d', number))[0]

def floating(word):
    return struct.unpack('>d', struct.pack('>Q', word))[0]

def literal(word):
    return f'F.fromBits({word >> 32}, {word & 0xFFFFFFFF})'

def divide(x, y):
    if y == 0:
        if x == 0 or math.isnan(x):
            return math.nan
        return math.copysign(math.inf, math.copysign(1, x) * math.copysign(1, y))
    return x / y

edges = [0, 1 << 63, 1, (1 << 63) | 1, (1 << 52) - 1, 1 << 52,
         bits(1.0), bits(-1.0), bits(2.0), 0x7FEFFFFFFFFFFFFF,
         0xFFEFFFFFFFFFFFFF, bits(math.inf), bits(-math.inf),
         0x7FF8000000000001, 0x7FF0000000000001]
vectors = [(a, b) for a in edges for b in edges]
rng = random.Random(6400852)
vectors += [(rng.getrandbits(64), rng.getrandbits(64)) for _ in range(256)]
for _ in range(256):
    exponent = rng.randrange(1, 2045)
    a = (rng.getrandbits(1) << 63) | (exponent << 52) | rng.getrandbits(52)
    b = (rng.getrandbits(1) << 63) | ((exponent + rng.randrange(-1, 2)) << 52) | rng.getrandbits(52)
    vectors.append((a, b))
# Halfway cases exercise both even and odd significands. Neighbors probe
# guard/round/sticky information on either side of the tie.
for exponent in [-1022, -1000, -53, 0, 52, 900, 1023]:
    a = math.ldexp(1.0, exponent)
    half = math.ldexp(1.0, exponent - 53)
    for base in [a, math.nextafter(a, math.inf), -a]:
        for delta in [half, -half, math.nextafter(half, 0), math.nextafter(half, math.inf)]:
            vectors.append((bits(base), bits(delta)))

# Densely sample gradual underflow and normal/subnormal transitions.
for _ in range(256):
    a = (rng.getrandbits(1) << 63) | (rng.randrange(5) << 52) | rng.getrandbits(52)
    b = (rng.getrandbits(1) << 63) | (rng.randrange(1018, 1028) << 52) | rng.getrandbits(52)
    vectors.append((a, b))
# Integer conversion must round both sides of the 53-bit precision boundary.
integer_edges = [0, 1, (1 << 53)-1, 1 << 53, (1 << 53)+1, (1 << 53)+2,
                 (1 << 53)+3, (1 << 64)-1]

source = ['import Base', 'import ../packages/runtime/src/f64.bend as F', 'import ../packages/runtime/src/u64.bend as W',
          'import ../packages/runtime/test/f64-support.bend as H']
for index, (a, b) in enumerate(vectors):
    x, y = floating(a), floating(b)
    order = 3 if math.isnan(x) or math.isnan(y) else 0 if x < y else 1 if x == y else 2
    integer = integer_edges[index] if index < len(integer_edges) else rng.getrandbits(64)
    integer_literal = f'W.U64{{{integer >> 32}, {integer & 0xFFFFFFFF}}}'
    source.append(f'def case{index}() -> H.Case:\n  H.Case{{"vector {index}", {literal(a)}, {literal(b)}, {literal(bits(x+y))}, {literal(bits(x-y))}, {literal(bits(x*y))}, {literal(bits(divide(x,y)))}, {order}, {integer_literal}, {literal(bits(float(integer)))}}}')
source.append('def main() -> IO(Unit):\n  H.checkAll(' + ' <> '.join(f'case{i}()' for i in range(len(vectors))) + ' <> Nil{})')
pathlib.Path('build').mkdir(exist_ok=True)
pathlib.Path('build/f64-vectors.bend').write_text('\n\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'build/f64-vectors.bend', 'build/test-f64'], check=True)
subprocess.run(['build/test-f64', '--threads', '1'], check=True, timeout=60)
print(f'f64: {len(vectors)} vectors passed (signed zeros, subnormals, ties, cancellation, overflow, infinities, NaNs)')
