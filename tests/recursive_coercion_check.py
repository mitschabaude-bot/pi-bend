"""Compare recursive coercion with the pinned helper, including its real cache."""
from upstream_pin import UPSTREAM, check_sibling
check_sibling()
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
assert json.loads((UPSTREAM / 'packages/ai/package.json').read_text())['dependencies']['typebox'] == '1.3.27'
cases = []
def case(schema, instance, name, pending=False):
    cases.append({'schema': schema, 'value': instance, 'name': name, 'pending': pending})

scalars = [None, True, False, 0, 1, 1.5, '', '42', 'true', 'false', 'bad', [], {}]
for t in ['number', 'integer', 'boolean', 'string', 'null', ['number', 'string'], ['boolean', 'integer'], ['array', 'null']]:
    for v in scalars:
        case({'type': t}, v, f'primitive phase {t}/{v}')
for key in ['anyOf', 'oneOf']:
    for members in [[{'type': 'number'}, {'type': 'null'}], [{'type': 'number'}, {'type': 'string'}],
                    [{'type': 'boolean'}, {'type': 'number'}], [{'type': 'integer', 'minimum': 10}, {'type': 'boolean'}],
                    [False, {'type': 'number'}], []]:
        for v in scalars:
            case({key: members}, v, f'{key} {members}/{v}')
for members in [[{'type': 'number'}, {'type': 'string'}], [{'type': 'string'}, {'type': 'boolean'}],
                [{'type': 'boolean'}, {'type': 'integer'}], []]:
    for v in scalars:
        case({'allOf': members}, v, f'ordered allOf {members}/{v}')
obj = {'type': 'object', 'properties': {'x': {'type': 'number'}}, 'additionalProperties': {'type': 'boolean'}}
for schema in [obj, {'properties': obj['properties']},
               {'type': ['object', 'null'], 'properties': obj['properties']},
               {'type': 'object', 'properties': {'nested': obj}},
               {'type': 'array', 'items': obj},
               {'type': 'array', 'items': [obj, {'type': 'number'}]},
               {'type': 'array', 'items': [{'type': 'number'}], 'additionalItems': {'type': 'boolean'}},
               {'items': obj}, {'type': 'object', 'additionalProperties': False}]:
    for v in [{'x': '42', 'y': 'true'}, {'x': None, 'y': 'false'}, {'y': '1'}, {},
              {'nested': {'x': '2', 'y': 'true'}}, [{'x': '2', 'y': 'false'}, '3', 'true'], ['2', 'true'], None]:
        case(schema, v, f'aggregate {schema}/{v}')
# Failed candidate changes must not leak into the next candidate or fallback.
first = {'type': 'object', 'properties': {'x': {'type': 'number'}}, 'required': ['missing']}
second = {'type': 'object', 'properties': {'y': {'type': 'number'}}, 'required': ['y']}
case({'anyOf': [first, second]}, {'x': '1', 'y': '2'}, 'independent union candidates')
case({'anyOf': [first]}, {'x': '1'}, 'failed union leaves original intact')
case({'anyOf': [{'type': 'number'}, {'type': 'string'}], 'type': 'boolean'}, 'true', 'parent scalar phase follows union')
case({'allOf': [{'type': 'number'}], 'anyOf': [{'type': 'string'}], 'oneOf': [{'type': 'boolean'}, {'type': 'integer'}]}, '1', 'composition phase order')
case({'anyOf': [True, {'type': 'number'}]}, '42', 'boolean-key cache decision', True)
expected = json.loads(subprocess.check_output(['node', 'tests/recursive_coercion_reference.mjs'],
                      input=json.dumps(cases), text=True, cwd=ROOT))
assert expected[-5] == {'x': '1', 'y': 2}
assert expected[-4] == {'x': '1'}
assert expected[-1] == 42  # Literal true cannot enter upstream's WeakMap cache.
lines = ['import Base', 'import ../packages/ai/test/recursive-coercion.bend as T',
         'import ../packages/ai/src/utils/validation.bend as Validation',
         'import ../packages/runtime/src/schema-value.bend as V',
         'import ../packages/runtime/src/f64.bend as F',
         'import ../packages/runtime/src/record.bend as R']
pending = 0
for i, (fixture, result) in enumerate(zip(cases, expected, strict=True)):
    lines += [f'def case{i}() -> IO(Unit):']
    if fixture['pending']:
        pending += 1
        lines.append(f'  T.pending(Validation.coerceWithJsonSchema({value(fixture["value"])}, {value(fixture["schema"])}))')
    else:
        lines.append(f'  T.check({value(fixture["value"])}, {value(fixture["schema"])}, {value(result)}, {value(fixture["value"])}, {json.dumps(fixture["name"])})')
lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
lines += [f'    case{i}()' for i in range(len(cases))]
lines += [f'    IO.print("PASS {len(cases) - pending} upstream recursive coercion cases; {pending} explicit pending decision")']
source = BUILD / 'recursive-coercion-check.bend'
source.write_text('\n'.join(lines) + '\n')
for source, name in [(source, 'recursive-coercion-check'), ('packages/ai/test/recursive-coercion.bend', 'recursive-coercion-errors')]:
    output = BUILD / name
    subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=120)
