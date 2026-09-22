"""Bit-exact remainder oracle using the host's independently implemented fmod."""
import math, random, struct, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build';BUILD.mkdir(exist_ok=True)
def number(word):return struct.unpack('>d',struct.pack('>Q',word))[0]
def bits(value):return struct.unpack('>Q',struct.pack('>d',value))[0]
def literal(word):return f'F.fromBits({word>>32}, {word&0xffffffff})'
words=[0,1,2,0xfffffffffffff,0x10000000000000,0x3fb999999999999a,0x3ff0000000000000,0x4008000000000000,0x4330000000000000,0x7fefffffffffffff,0x7ff0000000000000,0x7ff8000000000000]
words += [w|1<<63 for w in words]
cases=[(a,b) for a in words for b in words]
rng=random.Random(6400854)
cases += [(rng.getrandbits(64),rng.getrandbits(64)) for _ in range(400)]
lines=['import Base','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/f64.bend as Rem','import ../packages/runtime/src/u64.bend as W','import ../packages/runtime/test/schema.bend as T']
for i,(a,b) in enumerate(cases):
    try:expected=math.fmod(number(a),number(b))
    except ValueError:expected=math.nan
    expression=f'Rem.remainder({literal(a)}, {literal(b)})'
    check=f'F.isNaN({expression})' if math.isnan(expected) else f'W.equal(F.toBits({expression}), F.toBits({literal(bits(expected))}))'
    lines += [f'def case{i}() -> IO(Unit):',f'  T.assertion({check}, "remainder {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} binary64 remainder comparisons")']
src=BUILD/'f64-remainder-vectors.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'test-f64-remainder'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
