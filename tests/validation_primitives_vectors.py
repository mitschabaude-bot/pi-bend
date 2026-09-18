"""Differential tests for the original validation type predicates."""
import json
from pathlib import Path
import random
import subprocess
from schema_test_values import valid, bend, string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
kinds=['number','integer','boolean','string','null','array','object','unknown','', 'Number']
bits={0,1,0x8000000000000000,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000000000,0x7ff0000000000001}
# Sweep exponent boundaries and fraction tails, including the 2^52 boundary
# where every representable finite value becomes integral.
for exponent in [0,1,1022,1023,1024,1054,1055,1074,1075,1076,2046,2047]:
 for fraction in [0,1,0x80000000,0x100000000,0x8000000000000,0xfffffffffffff]:
  for sign in [0,1]: bits.add(sign<<63|exponent<<52|fraction)
rng=random.Random(85117)
bits.update(rng.getrandbits(64) for _ in range(128))
values=[['number',f'{b:016x}'] for b in sorted(bits)]
values += [['null'],['boolean',False],['boolean',True],['string',[]],['string',[49]],['array',[]],['object',[],[]]]
schemas=[['null'],['boolean',False],['number','3ff0000000000000'],['string',[]],['string',list(map(ord,'number'))],['array',[]],['array',[['string',list(map(ord,'integer'))],['null'],['string',list(map(ord,'integer'))],['boolean',True],['string',[]],['array',[]]]]]
# JS-only dynamic values are intentionally outside the Bend API.
values = [v for v in values if valid(v)]
schemas = [v for v in schemas if valid(v)]
reference=json.loads(subprocess.check_output(['node','tests/validation_primitives_reference.mjs'],input=json.dumps(dict(values=values,kinds=kinds,schemas=schemas)),text=True,cwd=ROOT))
assert reference['missing']==[]
lines=['import Base','import ../packages/ai/test/validation-primitives.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B','import ../packages/runtime/src/record.bend as R']
# Separate functions keep native compiler expression size bounded without
# reducing the independently checked cases.
for i,(value,expected) in enumerate(zip(values,reference['matches'],strict=True)):
 lines += [f'def case{i}() -> IO(Unit):','  do IO<Unit>:']
 for kind,result in zip(kinds,expected,strict=True):
  lines.append(f'    T.check({bend(value)}, {json.dumps(kind)}, '+('True{}' if result else 'False{}')+')')
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']
lines += [f'    case{i}()' for i in range(len(values))]
for value,expected in zip(schemas,reference['types'],strict=True):
 for _ in [None]:
  items=' <> '.join([string(map(ord,s)) for s in expected]+['Nil{}'])
  lines.append(f'    T.checkTypes({bend(value)}, {items})')
lines += ['    T.missingType()']
lines += [f'    IO.print("PASS {len(values)*len(kinds)} upstream type predicates and {len(schemas)} schema type filters")']
source=BUILD/'validation-primitives-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-validation-primitives'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
 subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=60)
