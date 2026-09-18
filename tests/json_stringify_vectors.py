"""Differential canonical JsonValue serialization and UTF-16 quoting tests."""
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
rng = random.Random(160055)
points = list(range(32)) + [34, 47, 92, 127, 0x2028, 0x2029, 0xd7ff, 0xd800,
    0xdbff, 0xdc00, 0xdfff, 0xe000, 0xffff, 0x10000, 0x1f600, 0x10ffff]
strings = [[], *[[point] for point in points],
    [0xd83d, 0xde00], [0x1f600], [0xd800, 0xd800, 0xdc00],
    [0xdbff, 0xdfff], [0xdc00, 0xd800], [0xd800, 65], [0xd800, 0x1f600]]
strings += [[unit] for unit in range(0, 65536, 97)]
strings += [[rng.choice(points) for _ in range(rng.randrange(2, 30))] for _ in range(128)]
strings += [[rng.randrange(0x110000) for _ in range(12)] for _ in range(32)]
numbers = ['0000000000000000', '8000000000000000', '3ff0000000000000',
    'bff0000000000000', '3fb999999999999a', '3e7ad7f29abcaf48',
    '444b1ae4d6e2ef50', '7fefffffffffffff', '0000000000000001',
    '7ff0000000000000', 'fff0000000000000', '7ff8000000000001']
keys = [[ord(c) for c in key] for key in ['2', '10', '01', '0', 'a', '__proto__', 'constructor', '']]
keys += [[0xd83d, 0xde00], [0x1f600], [0xd800]]

def tree(depth):
    choice = rng.randrange(6 if depth else 4)
    if choice == 0:
        return ['null']
    if choice == 1:
        return ['boolean', bool(rng.randrange(2))]
    if choice == 2:
        return ['number', rng.choice(numbers)]
    if choice == 3:
        return ['string', rng.choice(strings)]
    if choice == 4:
        return ['array', [tree(depth-1) for _ in range(rng.randrange(5))]]
    return ['object', [[rng.choice(keys), tree(depth-1)] for _ in range(rng.randrange(6))]]

values = [['null'], ['boolean', True], ['boolean', False], ['array', []], ['object', []]]
values += [['number', value] for value in numbers]
values += [['object', [[[0xd83d, 0xde00], ['boolean', False]], [[0x1f600], ['boolean', True]], [[50], ['null']], [[49, 48], ['array', []]]]]]
values += [tree(4) for _ in range(96)]
oracle = '''const input = JSON.parse(process.argv[1]);
const str = points => String.fromCodePoint(...points);
function value(item) {
  switch(item[0]) {
    case 'null': return null;
    case 'boolean': return item[1];
    case 'string': return str(item[1]);
    case 'number': { const data=Buffer.alloc(8); data.writeBigUInt64BE(BigInt('0x'+item[1])); return data.readDoubleBE(); }
    case 'array': return item[1].map(value);
    case 'object': { const out=Object.create(null); for(const [key,child] of item[1]) out[str(key)]=value(child); return out; }
  }
}
console.log(JSON.stringify({strings: input.strings.map(x=>JSON.stringify(str(x))), values: input.values.map(x=>JSON.stringify(value(x)))}));'''
expected = json.loads(subprocess.check_output(['node', '-e', oracle, json.dumps({'strings': strings, 'values': values})], text=True))

def string(points):
    result = 'SNil{}'
    for code in reversed(points):
        result = f'SCon{{Chr{{{code}}}, {result}}}'
    return result

def bend(value):
    kind = value[0]
    if kind == 'null': return 'T.JsonNull{}'
    if kind == 'boolean': return 'T.JsonBoolean{' + ('True{}' if value[1] else 'False{}') + '}'
    if kind == 'number':
        raw = int(value[1], 16)
        return f'T.JsonNumber{{F.fromBits({raw >> 32}, {raw & 0xffffffff})}}'
    if kind == 'string': return 'T.JsonString{' + string(value[1]) + '}'
    if kind == 'array': return 'T.JsonArray{' + ' <> '.join([bend(child) for child in value[1]] + ['Nil{}']) + '}'
    record = 'R.new(T.JsonValue)'
    for key, child in value[1]:
        record = f'R.set(T.JsonValue, {record}, {string(key)}, {bend(child)})'
    return 'T.JsonObject{' + record + '}'

source = '''import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/json.bend as J
import ../packages/runtime/src/json-string.bend as S
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F

def check(actual: Maybe<&2, String>, +expected: String, label: String) -> IO(Unit):
  match actual:
    case None{}: IO.die(Unit, 1, label ++ " numeric conversion failed")
    case Some{+value}: Bool.pick(IO(Unit), String.eq(value, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, label ++ " expected " ++ expected ++ " got " ++ value))

def main() -> IO(Unit):
  do IO<Unit>:
'''
for index, (points, output) in enumerate(zip(strings, expected['strings'], strict=True)):
    source += f'    check(Some{{S.quote({string(points)})}}, {json.dumps(output, ensure_ascii=False)}, "quote {index}")\n'
for index, (value, output) in enumerate(zip(values, expected['values'], strict=True)):
    source += f'    check(J.stringify({bend(value)}), {json.dumps(output, ensure_ascii=False)}, "JSON {index}")\n'
source += f'    IO.print("JSON: {len(strings)} quoting and {len(values)} structured JavaScript vectors passed")\n'
entry = BUILD / 'json-stringify-vectors.bend'
entry.write_text(source)
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/test-json-stringify'], cwd=ROOT, check=True)
subprocess.run(['build/test-json-stringify', '--threads', '1'], cwd=ROOT, check=True, timeout=240)
