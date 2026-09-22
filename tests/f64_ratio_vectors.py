"""Exact rational rounding oracle, independent of the Bend search algorithm."""
from fractions import Fraction
import math
from pathlib import Path
import random
import struct
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
def big(value):
    limbs=[]
    while value:
        limbs.append(str(value & 0xFFFFFFFF))
        value >>= 32
    return 'B.BigNat{'+' <> '.join(limbs+['Nil{}'])+'}'
def bits(value):return struct.unpack('>Q',struct.pack('>d',value))[0]
def exact(word):return Fraction.from_float(struct.unpack('>d',struct.pack('>Q',word))[0])
values=[(False,0,0),(True,1,0),(False,0,1),(True,0,1),(False,1,3),(True,1,10)]
# Exact midpoints and tiny offsets on either side, at subnormal and normal
# boundaries, odd/even significands, and the finite/infinity threshold.
for word in [0,1,2,0xffffffffffffe,0xfffffffffffff,0x10000000000000,0x3fefffffffffffff,0x3ff0000000000000,0x3ff0000000000001,0x4330000000000000,0x7feffffffffffffe,0x7fefffffffffffff]:
    lower=exact(word)
    upper=Fraction(1<<1024) if word==0x7fefffffffffffff else exact(word+1)
    middle=(lower+upper)/2
    for value in [lower,middle-(upper-lower)/2**80,middle,middle+(upper-lower)/2**80,upper]:
        for sign in [False,True]:values.append((sign,value.numerator,value.denominator))
rng=random.Random(6400853)
for _ in range(96):
    values.append((bool(rng.randrange(2)),rng.getrandbits(rng.randrange(1,2200)),rng.getrandbits(rng.randrange(1,2200)) or 1))
# Equal large operands must become one without independently overflowing.
values += [(False,10**1000,10**1000),(True,10**1000+1,10**1000),(False,1,10**1000),(True,10**1000,1)]
lines=['import Base','import ../packages/runtime/test/f64-ratio.bend as T','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B']
for i,(sign,n,d) in enumerate(values):
    expected='None{}'
    if d:
        try: value=float(Fraction(n,d))
        except OverflowError: value=math.inf
        raw=bits(-value if sign else value)
        expected=f'Some{{F.fromBits({raw>>32}, {raw & 0xffffffff})}}'
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check('+('True{}' if sign else 'False{}')+f', {big(n)}, {big(d)}, {expected}, "ratio {i}")']
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(values))]+[f'    IO.print("PASS {len(values)} exact rational rounding cases")']
source=BUILD/'f64-ratio-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-f64-ratio'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
