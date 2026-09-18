"""Compare schema-data snapshots with JavaScript JSON round trips."""
import json
from pathlib import Path
import random
import subprocess
from typebox_fixtures import fixtures

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
rng = random.Random(8511600)
keys = ['a', '0', '2', '10', '01', 'constructor', '__proto__', 'description']
numbers = ['0000000000000000', '8000000000000000', '3fb999999999999a',
           '7ff0000000000000', 'fff0000000000000', '7ff8000000000001', '0000000000000001']

def tree(depth):
    kind = rng.randrange(10 if depth else 8)
    if kind == 0: return ['undefined']
    if kind == 1: return ['null']
    if kind == 2: return ['boolean', bool(rng.randrange(2))]
    if kind == 3: return ['number', rng.choice(numbers)]
    if kind == 4: return ['string', [rng.choice([34, 65, 0xd800, 0xdc00, 0x1f600]) for _ in range(5)]]
    if kind == 5: return ['symbol', rng.randrange(20)]
    if kind == 6: return ['callable', rng.randrange(20)]
    if kind == 7: return ['bigint']
    if kind == 8: return ['array', [tree(depth-1) for _ in range(rng.randrange(5))]]
    return ['object', [[rng.choice(keys), tree(depth-1), bool(rng.randrange(2))] for _ in range(rng.randrange(6))], [[1, tree(depth-1)]]]

values = [['undefined'], ['null'], ['symbol', 1], ['callable', 2], ['bigint']]
values += [['number', x] for x in numbers]
values += [['array', [['undefined'], ['symbol', 1], ['callable', 2], ['null']]],
           ['object', [['keep', ['boolean', True], True], ['drop', ['undefined'], True], ['hidden', ['bigint'], False]], [[1, ['bigint']]]],
           ['object', [['kind', ['string', [111, 98, 106, 101, 99, 116]], True]], [[1, ['string', [79, 98, 106, 101, 99, 116]]]]]]
# JSON Schema object data with TypeBox-like symbol metadata, optional undefined
# annotations and an executable-valued extra field. This is data projection,
# not a substitute for the TypeBox builder or validator APIs.
values += [['object', [['type', ['string', list(map(ord, 'object'))], True],
                       ['properties', ['object', [], []], True],
                       ['description', ['undefined'], True],
                       ['execute', ['callable', 7], True]],
                      [[1, ['string', list(map(ord, 'Object'))]]]]]
values += [tree(4) for _ in range(128)]
typebox = fixtures(ROOT)
values += [case['input'] for case in typebox]
oracle = '''const items = JSON.parse(process.argv[1]);
function build(v) {
  switch(v[0]) {
    case 'undefined': return undefined;
    case 'null': return null;
    case 'boolean': return v[1];
    case 'number': { const b=Buffer.alloc(8); b.writeBigUInt64BE(BigInt('0x'+v[1])); return b.readDoubleBE(); }
    case 'string': return String.fromCodePoint(...v[1]);
    case 'symbol': return Symbol.for(String(v[1]));
    case 'callable': return () => { throw new Error('ordinary callback must not be called'); };
    case 'bigint': return 1n;
    case 'array': return v[1].map(build);
    case 'object': { const out=Object.create(null); for (const [k,x,e] of v[1]) Object.defineProperty(out,k,{value:build(x),enumerable:e,configurable:true}); for(const [k,x] of v[2]) out[Symbol.for(String(k))]=build(x); return out; }
  }
}
function wire(v) {
  if(v===null) return ['null'];
  if(typeof v==='boolean') return ['boolean',v];
  if(typeof v==='number') { const b=Buffer.alloc(8); b.writeDoubleBE(v); return ['number',b.toString('hex')]; }
  if(typeof v==='string') return ['string',Array.from(v,c=>c.codePointAt(0))];
  if(Array.isArray(v)) return ['array',v.map(wire)];
  return ['object',Object.entries(v).map(([k,x])=>[k,wire(x),true]),[]];
}
console.log(JSON.stringify(items.map(v=>{try {const text=JSON.stringify(build(v)); return text===undefined ? ['absent'] : ['value',wire(JSON.parse(text)),text];} catch(e) {if(e instanceof TypeError) return ['bigint-error']; throw e;}})));'''
expected = json.loads(subprocess.check_output(['node', '-e', oracle, json.dumps(values)], text=True))
# Confirm the descriptor-tree transport itself preserves actual TypeBox JSON.
for case, result in zip(typebox, expected[-len(typebox):], strict=True):
    assert result[0] == 'value' and result[2] == case['json']

def string(points):
    result = 'SNil{}'
    for point in reversed(list(points)): result = f'SCon{{Chr{{{point}}}, {result}}}'
    return result

def bend(v):
    kind = v[0]
    if kind == 'undefined': return 'V.Undefined{}'
    if kind == 'null': return 'V.Null{}'
    if kind == 'boolean': return 'V.Boolean{' + ('True{}' if v[1] else 'False{}') + '}'
    if kind == 'number':
        raw=int(v[1],16)
        return f'V.Number{{F.fromBits({raw >> 32}, {raw & 0xffffffff})}}'
    if kind == 'string': return 'V.Text{' + string(v[1]) + '}'
    if kind == 'symbol': return f'V.Symbol{{{v[1]}}}'
    if kind == 'callable': return f'V.Callable{{{v[1]}}}'
    if kind == 'bigint': return 'V.BigInteger{False{}, B.one()}'
    if kind == 'array': return 'V.ArrayValue{' + ' <> '.join([bend(x) for x in v[1]]+['Nil{}']) + '}'
    record='R.new(V.Property<V.Value<U32>>)'
    for key, value, enumerable in v[1]:
        record=f'R.set(V.Property<V.Value<U32>>, {record}, {string(map(ord,key))}, V.Property{{{bend(value)}, '+('True{}' if enumerable else 'False{}')+'})'
    symbols=' <> '.join([f'V.SymbolProperty{{{key}, {bend(value)}}}' for key,value in v[2]]+['Nil{}'])
    return f'V.ObjectValue{{{record}, {symbols}}}'

source=['import Base','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B','import ../packages/runtime/test/schema-value.bend as H','import ../packages/ai/test/schema-json.bend as J','def main() -> IO(Unit):\n  do IO<Unit>:']
for index,(value,result) in enumerate(zip(values,expected,strict=True)):
    target='V.Projected{None{}}' if result[0]=='absent' else 'V.BigIntError{}' if result[0]=='bigint-error' else 'V.Projected{Some{'+bend(result[1])+'}}'
    source.append(f'    H.check({bend(value)}, {target}, "schema snapshot {index}")')
    rendered = 'J.Omitted{}' if result[0]=='absent' else 'J.BigInt{}' if result[0]=='bigint-error' else 'J.Json{'+string(map(ord, result[2]))+'}'
    source.append(f'    J.check({bend(value)}, {rendered}, "schema JSON {index}")')
# Hook behavior is explicitly unsupported, not compared with a fake JS result.
for enumerable in (True,False):
    value=['object',[['toJSON',['callable',1],enumerable]],[]]
    source.append(f'    H.check({bend(value)}, V.UnsupportedToJSON{{}}, "callable toJSON must not be silently discarded")')
    source.append(f'    J.check({bend(value)}, J.Hook{{}}, "callable toJSON conversion error")')
source.append('    H.check(H.nested(U32.to_nat(2000), V.Undefined{}), V.Projected{Some{H.nested(U32.to_nat(2000), V.Null{})}}, "deep omitted array value")')
source.append('    H.check(H.nested(U32.to_nat(2000), V.BigInteger{False{}, B.one()}), V.BigIntError{}, "deep BigInt rejection")')
source.append('    J.check(H.nested(U32.to_nat(2000), V.Undefined{}), J.Json{J.repeat(U32.to_nat(2000), Chr{91}) ++ "null" ++ J.repeat(U32.to_nat(2000), Chr{93})}, "deep schema JSON")')
source.append('    J.check(H.nested(U32.to_nat(2000), V.BigInteger{False{}, B.one()}), J.BigInt{}, "deep JSON BigInt rejection")')
source.append(f'    IO.print("schema-value: {len(values)} JavaScript snapshot/serialization cases, hook errors and deep-tree checks passed")')
entry=BUILD/'schema-value-vectors.bend'
entry.write_text('\n'.join(source)+'\n')
subprocess.run(['sh','scripts/build-pure.sh',str(entry),'build/test-schema-value'],cwd=ROOT,check=True)
subprocess.run(['build/test-schema-value','--threads','1'],cwd=ROOT,check=True,timeout=90)
