"""Independent arbitrary-precision vectors; Python is a test oracle only."""
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
rng = random.Random(655360851)
edges = [0, 1, 2, 65535, 65536, 65537, 2**32-1, 2**32,
         2**64-1, 2**128, 2**256-1]
vectors = [(a, b) for a in edges for b in edges]
vectors += [(rng.getrandbits(bits), rng.getrandbits(rng.randrange(1, bits+1)))
            for bits in [53, 64, 127, 256, 512, 1074, 2048] for _ in range(8)]
vectors += [(5**1074, 10**300), (2**2200-1, 2**1074+1)]

def big(value):
    limbs = []
    while value:
        limbs.append(str(value & 0xFFFF))
        value >>= 16
    return 'B.BigNat{' + ' <> '.join(limbs + ['Nil{}']) + '}'

source = ['import Base', 'import ../packages/runtime/src/big-nat.bend as B',
          'import ../packages/runtime/test/big-nat.bend as H']
for i, (a, b) in enumerate(vectors):
    shift = [0, 1, 15, 16, 17, 32, 64, 1074][i % 8]
    small = [0, 1, 2, 10, 255, 65535, 65536, 2**32-1][i % 8]
    difference = f'Some{{{big(a-b)}}}' if a >= b else 'None{}'
    division = ('Some{B.Division{' + big(a//b) + ', ' + big(a%b) + '}}') if b else 'None{}'
    small_division = ('Some{B.SmallDivision{' + big(a//small) + ', ' + str(a%small) + '}}'
                      if 0 < small <= 65535 else 'None{}')
    order = 'LT{}' if a < b else 'EQ{}' if a == b else 'GT{}'
    source.append(f'def case{i}() -> H.Case:\n  H.Case{{"vector {i}", {big(a)}, {big(b)}, {shift}n, {big(a+b)}, {big(a*b)}, {difference}, {division}, {big(a << shift)}, {order}, "{a}", {small}, {small_division}}}')
source.append('def main() -> IO(Unit):\n  do IO<Unit>:\n    H.checkAll(' + ' <> '.join(f'case{i}()' for i in range(len(vectors))) + ' <> Nil{})')
for base, exponent in [(0, 0), (0, 1), (1, 1074), (2, 1074), (5, 1074), (65535, 20)]:
    source.append(f'    H.assertion(B.equal(B.power(B.fromU32({base}), U32.to_nat({exponent})), {big(base**exponent)}), "power {base}^{exponent}")')
for value in [0, 1, 65535, 65536, 2**32-1]:
    source.append(f'    H.assertion(B.equal(B.fromU32({value}), {big(value)}), "fromU32 {value}")')
# Modular exponentiation against Python's pow: odd moduli take the Montgomery
# ladder (RSA sizes, prime fields, base at or above the modulus, exponents 0
# and 1, modulus 1), even moduli the bit-serial reduction.
def bytes_of(exponent):
    digits = []
    while exponent:
        digits.append(str(exponent & 255))
        exponent >>= 8
    return ' <> '.join(list(reversed(digits)) + ['Nil{}']) if digits else 'Nil{}'
prime256 = 2**256 - 2**224 + 2**192 + 2**96 - 1
modexp = [(2, 10, 1000), (3, 0, 7), (3, 1, 7), (5, 3, 1), (2**70 + 3, 65537, 2**64 + 13),
          (2**64 + 13 + 5, 65537, 2**64 + 13), (7, 2**33, 2**66), (7, 2**33 + 1, 2**66 + 2),
          (rng.getrandbits(255), prime256 - 2, prime256), (rng.getrandbits(2047), 65537, rng.getrandbits(2048) | (1 << 2047) | 1),
          (rng.getrandbits(1023), rng.getrandbits(1024), rng.getrandbits(1024) | (1 << 1023) | 1), (65536, 65536, 65536 * 3),
          # Limb counts whose R^2 = R*2^(16k) takes the odd (doubling) step, and RSA-3072/4096 sizes.
          (rng.getrandbits(1039), 65537, rng.getrandbits(1040) | (1 << 1039) | 1), (rng.getrandbits(3071), 3, rng.getrandbits(3072) | (1 << 3071) | 1),
          (rng.getrandbits(4095), 65537, rng.getrandbits(4096) | (1 << 4095) | 1), (2**4096 - 5, 65537, rng.getrandbits(4096) | (1 << 4095) | 1)]
for i, (base, exponent, modulus) in enumerate(modexp):
    source.append(f'    H.assertion(B.equal(B.powerMod({bytes_of(exponent)}, {big(base)}, {big(modulus)}), {big(pow(base, exponent, modulus))}), "powerMod {i}")')

# Big-endian octets: odd lengths, leading zeros, and widths that pad or keep
# only the least significant bytes.
def octets(data):
    return ' <> '.join([str(b) for b in data] + ['Nil{}'])
for i, data in enumerate([b'', b'\x00', b'\x01', b'\x00\x00\x01\x02\x03', bytes(range(1, 256)), rng.randbytes(256), rng.randbytes(513)]):
    value = int.from_bytes(data, 'big')
    source.append(f'    H.assertion(B.equal(B.fromBigEndian({octets(data)}), {big(value)}), "fromBigEndian {i}")')
    for width in sorted({0, 1, len(data), len(data) + 3, max(len(data) - 1, 0)}):
        expected = (value % (256 ** width)).to_bytes(width, 'big')
        source.append(f'    H.assertion(H.sameBytes(B.toBigEndian({width}n, {big(value)}), {octets(expected)}), "toBigEndian {i} {width}")')

for invalid in ['', '+1', '-1', ' 1', '1 ', '1.0', '1e2', '1x', '١']:
    source.append(f'    H.assertion(H.sameMaybe(B.fromDecimal("{invalid}"), None{{}}), "reject decimal {invalid}")')
source.append('    H.assertion(H.sameMaybe(B.fromDecimal("000000123"), Some{B.fromU32(123)}), "leading zeros")')
source.append('    H.assertion(H.sameMaybe(B.fromDecimal("000000000"), Some{B.zero()}), "canonical zero")')
source.append(f'    IO.print("big-nat: {len(vectors)} arithmetic/division/decimal vectors and power/input edge cases passed")')
entry = BUILD / 'big-nat-vectors.bend'
entry.write_text('\n\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), 'build/test-big-nat'], cwd=ROOT, check=True)
subprocess.run(['build/test-big-nat', '--threads', '1'], cwd=ROOT, check=True, timeout=180)
