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
        limbs.append(str(value & 65535))
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
for invalid in ['', '+1', '-1', ' 1', '1 ', '1.0', '1e2', '1x', '١']:
    source.append(f'    H.assertion(H.sameMaybe(B.fromDecimal("{invalid}"), None{{}}), "reject decimal {invalid}")')
source.append('    H.assertion(H.sameMaybe(B.fromDecimal("000000123"), Some{B.fromU32(123)}), "leading zeros")')
source.append('    H.assertion(H.sameMaybe(B.fromDecimal("000000000"), Some{B.zero()}), "canonical zero")')
source.append(f'    IO.print("big-nat: {len(vectors)} arithmetic/division/decimal vectors and power/input edge cases passed")')
entry = BUILD / 'big-nat-vectors.bend'
entry.write_text('\n\n'.join(source) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/test-big-nat'], cwd=ROOT, check=True)
subprocess.run(['build/test-big-nat', '--threads', '1'], cwd=ROOT, check=True, timeout=180)
