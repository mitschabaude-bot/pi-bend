"""Compare the native typed schema evaluator with pi-ai's pinned TypeBox.

The fixture translator is deliberately test-only. Production JSON Schema
compilation, remaining keywords and diagnostics are still pending.
"""
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
upstream = ROOT.parent / 'pi-mono/packages/ai/package.json'
assert json.loads(upstream.read_text())['dependencies']['typebox'] == '1.3.27'
DEPENDENCY = BUILD / 'schema-reference/node_modules/typebox/package.json'
if not DEPENDENCY.exists():
    subprocess.run(['npm', 'install', '--prefix', str(BUILD / 'schema-reference'),
                    '--ignore-scripts', '--no-audit', '--no-fund', 'typebox@1.3.27'], check=True)
assert json.loads(DEPENDENCY.read_text())['version'] == '1.3.27'

values = [None, False, True, 0, 1, -1, 1.5, '', 'x', [], [None], [1], [1, 'x'],
          [1, False], [1, 'x', None], {}, {'x': None}, {'x': 1}, {'x': 'x'},
          {'x': 1, 'y': True}, {'x': 1, 'y': 'x'}, {'y': 1},
          {'nested': {'x': 1}}, {'nested': {'x': None}}, [{'x': 1}], [{'x': None}],
          {'a': 1, 'b': 2}, {'b': 2, 'a': 1}, {'__proto__': 1},
          {'toString': 'x'}, {'constructor': 1}]
schemas = [True, False, {}, *({'type': t} for t in
           ['null', 'boolean', 'number', 'integer', 'string', 'array', 'object']),
           {'type': ['integer', 'string']}, {'const': None}, {'const': {'a': 1, 'b': 2}},
           {'enum': [None, 'x', [1, 'x'], {'a': 1, 'b': 2}]},
           {'allOf': [{'type': 'number'}, {'not': {'const': 0}}]},
           {'anyOf': [{'type': 'integer'}, {'type': 'string'}]},
           {'oneOf': [{'type': 'integer'}, {'type': 'number'}]},
           {'oneOf': [{'type': 'integer'}, {'type': 'string'}]},
           {'not': {'anyOf': [{'type': 'null'}, {'type': 'object'}]}},
           {'properties': {'x': {'type': 'integer'}}, 'required': ['x']},
           {'type': 'object', 'properties': {'x': {'type': 'integer'}}, 'additionalProperties': False},
           {'type': 'object', 'properties': {'x': {'type': 'integer'}}, 'required': ['x'], 'additionalProperties': {'type': 'boolean'}},
           {'type': 'object', 'properties': {'nested': {'properties': {'x': {'type': 'number'}}, 'required': ['x']}}, 'required': ['nested']},
           {'type': 'array', 'items': {'type': 'integer'}},
           {'type': 'array', 'items': [{'type': 'integer'}, {'type': 'string'}]},
           {'type': 'array', 'items': [{'type': 'integer'}, {'type': 'string'}], 'additionalItems': False},
           {'items': {'properties': {'x': {'type': 'integer'}}, 'required': ['x']}},
           {'type': 'object', 'additionalProperties': {'anyOf': [{'type': 'number'}, {'type': 'boolean'}]}},
           {'anyOf': [{'type': 'array', 'items': {'type': 'integer'}}, {'type': 'object', 'required': ['x']}]},
           {'oneOf': [{'const': 1}, {'const': 1}, {'type': 'string'}]}]

values += [-0.0, 0.9999999999999999, 1.0000000000000002, 2, -2,
           [1, 1], [1, 2], [1, 2, 3], [None, None], [0, -0.0],
           [True, 1], [{'a': 1, 'b': 2}, {'b': 2, 'a': 1}],
           [[1, 2], [2, 1]], [[1, 2], [1, 2]]]
schemas += [
    *({key: bound} for key in ['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum']
      for bound in [-1, 0, 1]),
    {'type': 'number', 'minimum': -1, 'maximum': 1},
    {'minimum': 1, 'maximum': 0},
    {'minItems': 1}, {'maxItems': 1}, {'minItems': 1, 'maxItems': 2},
    {'minItems': 2, 'maxItems': 1},
    {'minProperties': 1}, {'maxProperties': 1},
    {'minProperties': 1, 'maxProperties': 2},
    {'contains': {'type': 'integer'}},
    {'contains': {'type': 'integer'}, 'minContains': 0},
    {'contains': {'type': 'integer'}, 'minContains': 2},
    {'contains': {'type': 'integer'}, 'maxContains': 1},
    {'contains': {'type': 'integer'}, 'minContains': 0, 'maxContains': 0},
    {'contains': {'type': 'integer'}, 'minContains': 2, 'maxContains': 1},
    {'contains': {'properties': {'x': {'type': 'number'}}, 'required': ['x'], 'type': 'object'}},
    {'type': 'array', 'contains': {'type': 'integer'}, 'minItems': 2},
    {'minContains': 100, 'maxContains': 0},
]

# Native maps treat these as ordinary strings. Exclude prototype-sensitive
# schemas from the JS oracle; dedicated native checks below assert that policy.
expected = json.loads(subprocess.check_output(
    ['node', 'tests/schema_reference.mjs'], cwd=ROOT,
    input=json.dumps({'schemas': schemas, 'values': values}), text=True))


def seq(items):
    return ' <> '.join([*items, 'Nil{}'])


def floating(v):
    hi, lo = struct.unpack('>II', struct.pack('>d', v))
    return f'F.fromBits({hi}, {lo})'


def value(v):
    if v is None:
        return 'V.Null{}'
    if isinstance(v, bool):
        return f'V.Boolean{{{"True{}" if v else "False{}"}}}'
    if isinstance(v, (int, float)):
        return 'V.Number{' + floating(v) + '}'
    if isinstance(v, str):
        return 'V.Text{' + json.dumps(v) + '}'
    if isinstance(v, list):
        return 'V.ArrayValue{' + seq(map(value, v)) + '}'
    return 'V.ObjectValue{R.Record{' + seq('R.Property{' + json.dumps(k) + ', ' + value(x) + '}' for k, x in v.items()) + '}}'


def schema(s):
    if isinstance(s, bool):
        return 'S.Accept{}' if s else 'S.Reject{}'
    allowed = {'type', 'const', 'enum', 'allOf', 'anyOf', 'oneOf', 'not',
               'properties', 'required', 'additionalProperties', 'items', 'additionalItems',
               'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum',
               'minItems', 'maxItems', 'minProperties', 'maxProperties',
               'contains', 'minContains', 'maxContains'}
    assert set(s) <= allowed
    nodes = []
    if 'type' in s:
        types = s['type'] if isinstance(s['type'], list) else [s['type']]
        nodes.append('S.Any{' + seq('S.JsonKind{S.' + t.title() + 'Type{}}' for t in types) + '}')
    if 'const' in s:
        nodes.append('S.Constant{' + value(s['const']) + '}')
    if 'enum' in s:
        nodes.append('S.Enumeration{' + seq(map(value, s['enum'])) + '}')
    for key, node in [('allOf', 'All'), ('anyOf', 'Any'), ('oneOf', 'One')]:
        if key in s:
            nodes.append('S.' + node + '{' + seq(map(schema, s[key])) + '}')
    if 'not' in s:
        nodes.append('S.Not{' + schema(s['not']) + '}')
    if set(s) & {'properties', 'required', 'additionalProperties'}:
        props = 'R.Record{' + seq('R.Property{' + json.dumps(k) + ', ' + schema(v) + '}' for k, v in s.get('properties', {}).items()) + '}'
        nodes.append('S.Object{' + props + ', ' + seq(map(json.dumps, s.get('required', []))) + ', ' + schema(s.get('additionalProperties', True)) + '}')
    for key, node, inclusive in [('minimum', 'Minimum', True), ('maximum', 'Maximum', True),
                                  ('exclusiveMinimum', 'Minimum', False), ('exclusiveMaximum', 'Maximum', False)]:
        if key in s:
            nodes.append('S.' + node + '{' + floating(s[key]) + ', ' + ('True{}' if inclusive else 'False{}') + '}')
    def bounds(min_key, max_key, default=0):
        minimum = s.get(min_key, default)
        maximum = s.get(max_key)
        assert isinstance(minimum, int) and minimum >= 0
        assert maximum is None or (isinstance(maximum, int) and maximum >= 0)
        return 'S.CountBounds{' + str(minimum) + 'n, ' + ('None{}' if maximum is None else 'Some{' + str(maximum) + 'n}') + '}'
    for lo, hi, node in [('minItems', 'maxItems', 'ItemCount'), ('minProperties', 'maxProperties', 'PropertyCount')]:
        if lo in s or hi in s:
            nodes.append('S.' + node + '{' + bounds(lo, hi) + '}')
    if 'contains' in s:
        nodes.append('S.Contains{' + schema(s['contains']) + ', ' + bounds('minContains', 'maxContains', 1) + '}')
    if 'items' in s:
        items = s['items']
        prefix = items if isinstance(items, list) else []
        rest = s.get('additionalItems', True) if isinstance(items, list) else items
        nodes.append('S.Array{' + seq(map(schema, prefix)) + ', ' + schema(rest) + '}')
    return 'S.All{' + seq(nodes) + '}'


lines = ['import Base', 'import ../packages/runtime/src/schema.bend as S',
         'import ../packages/runtime/src/schema-value.bend as V',
         'import ../packages/runtime/src/record.bend as R',
         'import ../packages/runtime/src/f64.bend as F',
         'import ../packages/agent/test/message-events.bend as T']
for i, (s, results) in enumerate(zip(schemas, expected, strict=True)):
    lines += [f'def case{i}() -> IO(Unit):', '  do IO<Unit>:', f'    +schema : S.Schema = {schema(s)}']
    for j, (v, result) in enumerate(zip(values, results, strict=True)):
        literal = 'True{}' if result else 'False{}'
        lines.append(f'    T.assertion(Bool.not(Bool.xor(S.check(schema, {value(v)}), {literal})), "schema {i}, value {j}")')
lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
lines += [f'    case{i}()' for i in range(len(schemas))]
lines += [f'    IO.print("PASS {len(schemas) * len(values)} native typed-schema checks against TypeBox 1.3.27")']
source = BUILD / 'schema-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-schema-check'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=120)

# Native dictionary and IEEE edge contracts intentionally avoid JS reflection.
native = BUILD / "test-native-schema-check"
subprocess.run(["sh", "scripts/build-pure.sh", "packages/runtime/test/schema.bend", str(native)], cwd=ROOT, check=True)
for threads in ["1", "4"]:
    subprocess.run([str(native), "--threads", threads], cwd=ROOT, check=True, timeout=120)
