"""Compare pure binary64 pricing and shared cost identity with pinned pi-mono."""
import json
from pathlib import Path
import random
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)

def bits(value):
    return struct.pack('>d', value).hex()

def case(prices, tiers, values):
    return [[bits(v) for v in prices], None if tiers is None else [[bits(t), [bits(v) for v in p]] for t,p in tiers],
            [None if v is None else bits(v) for v in values]]

# Original request-wide tier test inputs, plus additional numerical boundaries.
base = [5, 30, .5, 6.25]
tier = [[272000, [10,45,1,12.5]]]
cases = [case(base, tier, [200000,100000,72000,w,None,None,372000+w]) for w in (0,1)]
cases += [case(base, None, [1,2,3,4,long,None,10]) for long in (None,0,1,4,5)]
cases += [case(base, [[100,[7,8,9,10]], [10,[1,2,3,4]], [100,[20,21,22,23]]], [n,9,0,0,None,None,n+9]) for n in (10,11,100,101)]
cases += [case(base, [[-2,[99,99,99,99]], [-.5,[1,2,3,4]]], [n,1,0,0,None,None,1]) for n in (-1,0)]
for special in (float('nan'), float('inf'), float('-inf'), -0.0, 5e-324, 1.7976931348623157e308):
    cases.append(case([special,30,.5,6.25], tier, [1,2,3,4,1,None,10]))
    cases.append(case(base, [[special,[7,8,9,10]]], [300000,2,3,4,1,None,1]))
    cases.append(case(base, tier, [1,2,3,4,special,None,10]))
rng = random.Random(851900)
for _ in range(128):
    prices = [rng.randrange(-100,10000)/64 for _ in range(4)]
    tiers = [[rng.randrange(0,1000000), [rng.randrange(0,20000)/128 for _ in range(4)]] for _ in range(rng.randrange(5))]
    values = [rng.randrange(0,500000) for _ in range(4)] + [None if rng.randrange(3)==0 else rng.randrange(0,500000), rng.randrange(0,50000), rng.randrange(0,1000000)]
    cases.append(case(prices, tiers, values))
path = BUILD / 'model-cost-input.json'
path.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output(['node','tests/model_metadata_reference.mts',str(path),'cost'],cwd=ROOT,text=True))

def number(word):
    value = int(word,16)
    return f'F.fromBits({value >> 32}, {value & 0xffffffff})'

def optional(word):
    return 'None{}' if word is None else 'Some{' + number(word) + '}'

def pricing(prices, tiers):
    levels = 'None{}' if tiers is None else 'Some{' + ' <> '.join(['T.ModelCostTier{' + ', '.join([number(v) for v in p]+[number(t)]) + '}' for t,p in tiers]+['Nil{}']) + '}'
    return 'T.ModelCost{' + ', '.join([number(v) for v in prices]+[levels]) + '}'

source = ['import Base','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/f64.bend as F',
          'import ../packages/ai/test/model-cost.bend as H','def main() -> IO(Unit):','  do IO<Unit>:']
for index, ((prices, tiers, values), want) in enumerate(zip(cases, expected, strict=True)):
    counters = 'H.Counters{' + ', '.join([number(v) for v in values[:4]]+[optional(values[4]),optional(values[5]),number(values[6])])+'}'
    cost = 'T.UsageCost{' + ', '.join(number(v) for v in want)+'}'
    source.append(f'    H.check({pricing(prices, tiers)}, {counters}, {cost}, "model cost {index}")')
source.append(f'    IO.print("PASS {len(cases)} upstream cost vectors with pure returned costs")')
entry = BUILD / 'model-cost-vectors.bend'
entry.write_text('\n'.join(source)+'\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(entry),'build/test-model-cost'],cwd=ROOT,check=True)
for threads in ('1','4'):
    subprocess.run(['build/test-model-cost','--threads',threads],cwd=ROOT,check=True,timeout=90)

subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/model-cost.bend','build/test-model-cost-upstream'],cwd=ROOT,check=True)
subprocess.run(['build/test-model-cost-upstream','--threads','1'],cwd=ROOT,check=True,timeout=30)
