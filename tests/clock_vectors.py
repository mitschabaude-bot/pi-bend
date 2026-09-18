"""Exact monotonic interval conversion and clock-primitive backend regression."""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
BEND = os.environ.get('BEND', str(Path.home() / '.bend/bin/bend'))
MASK = (1 << 64) - 1
rng = random.Random(0xC10C)
vectors = []
# Subtract integer ticks before converting to binary64, as PerformanceNowImpl
# does in Node v24.18.0 src/node_perf.cc. Include small deltas at huge epochs.
for origin in (0, (1 << 32) - 1, (1 << 53) - 1, 1 << 53, (1 << 63) + 123, MASK - 1000):
    for delta in (0, 1, 2, 999, 1000, 999999, 1000000, 1000001, (1 << 32) - 1,
                  1 << 32, (1 << 53) - 1, 1 << 53, (1 << 53) + 1, MASK):
        vectors.append((origin, (origin + delta) & MASK))
for _ in range(192):
    origin = rng.getrandbits(64)
    delta = rng.getrandbits(rng.randrange(1, 65))
    vectors.append((origin, (origin + delta) & MASK))
reference = subprocess.run(['node', '-e', '''
const fs = require('node:fs');
const cases = JSON.parse(fs.readFileSync(0, 'utf8'));
console.log(JSON.stringify(cases.map(([origin, current]) => {
  const delta = BigInt.asUintN(64, BigInt(current) - BigInt(origin));
  const buffer = Buffer.alloc(8);
  buffer.writeDoubleBE(Number(delta) / 1e6);
  return buffer.toString('hex');
})));
'''], input=json.dumps([[str(a), str(b)] for a, b in vectors]), text=True, capture_output=True, check=True)
expected = json.loads(reference.stdout)


def word(value):
    return f'W.U64{{{value >> 32}, {value & 0xffffffff}}}'


lines = ['import Base', 'import ../packages/runtime/src/clock.bend as C',
         'import ../packages/runtime/src/u64.bend as W', 'import ../packages/runtime/src/f64.bend as F',
         'def check(origin: W.U64, current: W.U64, expected: W.U64) -> IO(Unit):',
         '  Bool.pick(IO(Unit), W.equal(F.toBits(C.elapsed(C.Clock{origin}, current)), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "clock conversion differs from binary64 reference"))',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for (origin, current), bits in zip(vectors, expected, strict=True):
    lines.append(f'    check({word(origin)}, {word(current)}, {word(int(bits, 16))})')
lines.append(f'    IO.print("PASS {len(vectors)} exact monotonic interval conversion vectors")')
source = BUILD / 'clock-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-clock-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)

subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/clock.bend', 'build/test-clock'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(BUILD / 'test-clock'), '--threads', threads], check=True, timeout=30)
# Test the compiler's second lowering, without using JS in native programs.
subprocess.run([BEND, 'packages/runtime/test/clock.bend', '-o', str(BUILD / 'test-clock.js')], cwd=ROOT, check=True)
# Bend's existing sleep effect uses bun:ffi, so exercise the JS backend in its
# supported Bun host. Node remains the independent numeric reference above.
bun = shutil.which('bun') or str(Path.home() / '.bun/bin/bun')
subprocess.run([bun, str(BUILD / 'test-clock.js')], check=True, timeout=30)
print('PASS exact clock arithmetic, native/JS primitive and clock-backed Event constructor')
