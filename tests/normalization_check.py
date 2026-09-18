"""Compare immutable Bend normalization with pi's actual optional-null helper."""
import json
from pathlib import Path
import subprocess
from schema_literals import value

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
dependency = BUILD / 'schema-reference/node_modules/typebox/package.json'
if not dependency.exists():
    subprocess.run(['npm', 'install', '--prefix', str(BUILD / 'schema-reference'),
                    '--ignore-scripts', '--no-audit', '--no-fund', 'typebox@1.3.27'], check=True)
assert json.loads(dependency.read_text())['version'] == '1.3.27'
assert json.loads((ROOT.parent / 'pi-mono/packages/ai/package.json').read_text())['dependencies']['typebox'] == '1.3.27'

cases = []
def case(schema, instance, name):
    cases.append({'schema': schema, 'value': instance, 'name': name})

case({'type': 'object', 'properties': {
    'path': {'type': 'string'}, 'offset': {'type': 'number'},
    'nullable': {'anyOf': [{'type': 'string'}, {'type': 'null'}]},
    'metadata': {'type': 'object', 'properties': {'enabled': {'type': 'boolean'}}}},
    'required': ['path', 'metadata']},
    {'path': 'file.txt', 'offset': None, 'nullable': None, 'metadata': {'enabled': None}},
    'treats null as omission for optional non-nullable properties')
case({'type': 'object', 'properties': {'value': {'$ref': '#/$defs/value'}},
      '$defs': {'value': {'anyOf': [{'type': 'number'}, {'type': 'null'}]}}},
     {'value': None}, 'preserves optional nulls whose referenced schema is nullable')
leaves = [True, False, {}, *({'type': t} for t in ['null', 'number', 'integer', 'boolean', 'string', 'object', 'array']),
          {'type': ['array', 'null'], 'items': {'type': 'string'}},
          {'anyOf': [{'type': 'number'}, {'type': 'null'}]},
          {'oneOf': [{'type': 'number'}, {'type': 'null'}]},
          {'oneOf': [{'type': 'null'}, {'type': 'null'}]},
          {'allOf': [{'not': {'type': 'null'}}]},
          {'enum': ['x', None]}, {'enum': ['x']}, {'const': None},
          {'properties': {'child': {'type': 'string'}}}, {'$ref': '#/$defs/anything'}]
for i, leaf in enumerate(leaves):
    for required in [[], ['x']]:
        schema = {'properties': {'x': leaf}, 'required': required}
        for instance in [{}, {'x': None}, {'x': '42'}, {'x': {'child': None}}, {'other': None}]:
            case(schema, instance, f'leaf {i}, required={bool(required)}, instance={instance}')
item = {'properties': {'x': {'type': 'string'}}}
for schema in [{'items': item}, {'items': [item]}, {'items': [True, item]},
               {'items': [False, item], 'additionalItems': item},
               {'items': True}, {'items': False}, {},
               {'allOf': [{'items': item}]}]:
    for instance in [[], [{'x': None}], [{'x': None}, {'x': None}], [None, {'x': None}], {'x': None}]:
        case(schema, instance, f'array traversal {schema}/{instance}')
for schema in [{'additionalProperties': item}, {'allOf': [item]}, {'anyOf': [item]}]:
    case(schema, {'x': None, 'extra': {'x': None}}, 'only direct properties/items are traversed')
expected = json.loads(subprocess.check_output(['node', 'tests/normalization_reference.mjs'],
                      input=json.dumps(cases), text=True, cwd=ROOT))
assert expected[0] == {'path': 'file.txt', 'nullable': None, 'metadata': {}}
assert expected[1] == {'value': None}
lines = ['import Base', 'import ../packages/ai/test/validation-normalize.bend as T',
         'import ../packages/runtime/src/schema-value.bend as V',
         'import ../packages/runtime/src/f64.bend as F',
         'import ../packages/runtime/src/record.bend as R',
         'import ../packages/ai/src/utils/validation.bend as Validation']
pending = 0
for i, (fixture, result) in enumerate(zip(cases, expected, strict=True)):
    schema = fixture['schema']
    instance = fixture['value']
    undecided = (isinstance(instance, dict) and 'x' in instance and instance['x'] is None
                 and schema.get('properties', {}).get('x', True) is False
                 and 'x' not in schema.get('required', []))
    if undecided:
        assert result == instance  # Actual upstream WeakMap failure preserves null.
        pending += 1
        lines += [f'def case{i}() -> IO(Unit):',
                  f'  T.pending(Validation.normalizeOptionalNulls({value(instance)}, {value(schema)}))']
    else:
        lines += [f'def case{i}() -> IO(Unit):',
                  f'  T.check({value(instance)}, {value(schema)}, {value(result)}, {value(instance)}, {json.dumps(fixture["name"])})']
lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
lines += [f'    case{i}()' for i in range(len(cases))]
lines += [f'    IO.print("PASS {len(cases) - pending} upstream optional-null normalization cases; {pending} explicit pending decision")']
source = BUILD / 'normalization-check.bend'
source.write_text('\n'.join(lines) + '\n')
for source, name in [(source, 'normalization-check'), ('packages/ai/test/validation-normalize.bend', 'normalization-errors')]:
    output = BUILD / name
    subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=120)
