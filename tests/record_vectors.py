#!/usr/bin/env python3
"""Use JavaScript's actual own-property behavior as a test-only oracle."""
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
rng = random.Random(9055)
keys = ['', '0', '00', '01', '1', '2', '10', '100', '-0', '-1', '+1', '1.0',
        '1e0', ' 1', '1 ', '4294967294', '4294967295', '4294967296',
        '9007199254740991', '9' * 50, '123abc', '__proto__', 'constructor',
        'toString', 'a', 'b', 'é', '💡', '١']
sequences = [[['set', key, i] for i, key in enumerate(keys)]]
sequences.append(sequences[0] + [['set', 'a', 99], ['delete', '0'],
                                ['set', '0', 42], ['delete', 'b'], ['set', 'b', 7]])
for _ in range(48):
    sequences.append([(['delete', rng.choice(keys)] if rng.randrange(4) == 0
                       else ['set', rng.choice(keys), rng.randrange(10000)])
                      for _ in range(rng.randrange(1, 100))])
oracle = '''const cases = JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map(ops => {
  const value = Object.create(null);
  for (const [op,key,item] of ops) {
    if (op === 'set') value[key] = item; else delete value[key];
  }
  return Object.entries(value);
})));'''
expected = json.loads(subprocess.check_output(
    ['node', '-e', oracle, json.dumps(sequences)], text=True))

def string(value):
    return json.dumps(value, ensure_ascii=False)

def bend_list(items):
    return ' <> '.join(items + ['Nil{}'])

source = '''import Base
import ../packages/runtime/src/record.bend as R

type Operation is Data:
  Set{key: String, value: U32}
  Delete{key: String}

def apply(operations: List<&2, Operation>, record: R.Record<U32>) -> R.Record<U32>:
  match operations:
    case Nil{}: record
    case Set{key, value} <> rest: apply(rest, R.set(U32, record, key, value))
    case Delete{key} <> rest: apply(rest, R.remove(U32, record, key))

def equal(actual: List<&2, R.Property<U32>>, expected: List<&2, R.Property<U32>>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case R.Property{a, x} <> restA R.Property{b, y} <> restB:
      String.eq(a, b) && U32.is_eq(x, y) && equal(restA, restB)
    case _ _: False{}

def assertion(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "record differs from JavaScript own properties")

def main() -> IO(Unit):
  do IO<Unit>:
'''
for operations, result in zip(sequences, expected, strict=True):
    ops = bend_list([f'Set{{{string(op[1])}, {op[2]}}}' if op[0] == 'set'
                     else f'Delete{{{string(op[1])}}}' for op in operations])
    props = bend_list([f'R.Property{{{string(key)}, {value}}}' for key, value in result])
    source += f'    assertion(equal(R.entries(U32, apply({ops}, R.new(U32))), {props}))\n'
source += f'    IO.print("record: {len(sequences)} JavaScript differential sequences passed")\n'
entry = BUILD / 'record-vectors.bend'
entry.write_text(source)
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/record-vectors'], cwd=ROOT, check=True)
subprocess.run(['build/record-vectors', '--threads', '1'], cwd=ROOT, check=True, timeout=60)
