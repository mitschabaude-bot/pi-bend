"""Compare pure-Bend shortest binary64 spelling with JavaScript String(number)."""
import json
import math
from pathlib import Path
import random
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
SIGN = 1 << 63
MASK = SIGN - 1
bits = {0, SIGN, 1, 2, 3, (1 << 52)-1, 1 << 52,
        0x7fefffffffffffff, 0x7ff0000000000000, 0xfff0000000000000,
        0x7ff8000000000000, 0xfff8000000000001}
bits.update(range(1, 65))
bits.update(range((1 << 52)-16, (1 << 52)+17))
for exponent in range(1, 2047, 37):
    center = exponent << 52
    bits.update([center-1, center, center+1])
for exponent in sorted(set(range(-324, 310, 17)) | {-7, -6, -5, 19, 20, 21, 22, 23, 308}):
    center = struct.unpack('>Q', struct.pack('>d', float(f'1e{exponent}')))[0]
    bits.update(n for n in (center-1, center, center+1) if 0 <= n <= MASK)
# The .25/.75 cases near 1e15 hit decimal midpoint ties in opposite directions.
for value in [1000000000000000.25, 1000000000000000.75, 0.1, 0.2, 0.3, 1.5, 1.25, 1.005, 2.2250738585072014e-308,
              9007199254740991, 9007199254740992, 1000000000000000100,
              1.2345678901234567, math.pi, math.e]:
    bits.add(struct.unpack('>Q', struct.pack('>d', float(value)))[0])
bits.update(value ^ SIGN for value in list(bits))
rng = random.Random(6410077)
bits.update(rng.getrandbits(64) for _ in range(256))
ordered = sorted(bits)
oracle = '''const out = JSON.parse(process.argv[1]).map(hex => {
const data = Buffer.alloc(8); data.writeBigUInt64BE(BigInt('0x'+hex));
const value = data.readDoubleBE();
return {decimal:String(value), json:JSON.stringify(value)}; }); console.log(JSON.stringify(out));'''
expected = json.loads(subprocess.check_output(
    ['node', '-e', oracle, json.dumps([f'{value:016x}' for value in ordered])], text=True))
source = '''import Base
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/f64.bend as D

def check(actual: Maybe<&2, String>, +expected: String, label: String) -> IO(Unit):
  match actual:
    case None{}: IO.die(Unit, 1, label ++ " internal conversion invariant failed")
    case Some{+value}:
      Bool.pick(IO(Unit), String.eq(value, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label ++ " expected " ++ expected ++ " got " ++ value))

def main() -> IO(Unit):
  do IO<Unit>:
'''
for raw, output in zip(ordered, expected, strict=True):
    text = output["decimal"]
    source += f'    check(D.toDecimal(F.fromBits({raw >> 32}, {raw & 0xffffffff})), {json.dumps(text)}, "{raw:016x}")\n'
for raw, output in zip(ordered, expected, strict=True):
    if (raw & MASK) == 0 or (raw & 0x7ff0000000000000) == 0x7ff0000000000000 or raw in {0x3fb999999999999a, 0x444b1ae4d6e2ef50}:
        source += f'    check(D.toJsonNumber(F.fromBits({raw >> 32}, {raw & 0xffffffff})), {json.dumps(output["json"])}, "JSON {raw:016x}")\n'
source += f'    IO.print("f64 decimal: {len(ordered)} JavaScript spelling vectors and JSON edge cases passed")\n'
entry = BUILD / 'f64-decimal-vectors.bend'
entry.write_text(source)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), 'build/test-f64-decimal'], cwd=ROOT, check=True)
subprocess.run(['build/test-f64-decimal', '--threads', '1'], cwd=ROOT, check=True, timeout=240)
