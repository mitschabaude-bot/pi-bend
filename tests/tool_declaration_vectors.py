"""Compare declaration snapshots/equality directly with pinned pi-mono code."""
import copy
import json
from pathlib import Path
import subprocess
from schema_test_values import bend, string
from typebox_fixtures import fixtures

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)

def text(value):
    return string(map(ord, value))

def tool(schema, name='a', description='a tool', sampling=None):
    return dict(name=name, description=description, parameters=schema, sampling=sampling)

schemas = [f['input'] for f in fixtures(ROOT)]
base = tool(schemas[0])
cases = [[tool(schema), tool(schema)] for schema in schemas]
cases += [[base, tool(schemas[0], description='changed')],
          [base, tool(schemas[0], name='different')],
          [base, tool(schemas[0], sampling=False)]]
# Hidden metadata differences disappear, while enumerable metadata survives.
for schema in schemas:
    changed = copy.deepcopy(schema)
    changed[1] += [['ignored', ['undefined'], True], ['execute', ['callable', 1], True],
                   ['hidden', ['bigint'], False]]
    changed[2] += [[10, ['bigint']]]
    cases.append([tool(schema), tool(changed)])
cases.append([tool(schemas[0]), tool(schemas[6])])
configs = [False, {'type': 'json_schema', 'strict': 'prefer'},
           {'strict': 'prefer', 'type': 'json_schema'},
           {'type': 'json_schema', 'strict': 'require'},
           {'type': 'grammar', 'variants': {'openai_lark': 'x', 'openai_regex': 'y'}},
           {'type': 'grammar', 'variants': {'openai_regex': 'y', 'openai_lark': 'x'}},
           {'variants': {'openai_lark': 'x', 'openai_regex': 'y'}, 'type': 'grammar'}]
for config in configs:
    cases.append([tool(schemas[0], sampling=config), tool(schemas[0], sampling=config)])
for a, b in ((1, 2), (1, 3), (4, 5), (4, 6)):
    cases.append([tool(schemas[0], sampling=configs[a]), tool(schemas[0], sampling=configs[b])])
cases += [[tool(['number', '8000000000000000']), tool(['number', '0000000000000000'])],
          [tool(['number', '7ff0000000000000']), tool(['null'])],
          [tool(['array', [['undefined']]]), tool(['array', [['null']]])],
          [tool(['object', [['b', ['null'], True], ['a', ['null'], True]], []]),
           tool(['object', [['a', ['null'], True], ['b', ['null'], True]], []])]]
for invalid in (['undefined'], ['symbol', 1], ['callable', 1], ['bigint']):
    cases += [[base, tool(invalid)], [tool(invalid), base]]
cases += [[tool(['bigint']), tool(['undefined'])], [tool(['undefined']), tool(['bigint'])]]
data = BUILD / 'tool-declaration-input.json'
data.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output([
    'node', 'tests/tool_declaration_reference.mts', str(data)
], cwd=ROOT, text=True))

def sampling(config):
    if config is None:
        return 'None{}'
    if config is False:
        return 'Some{T.SamplingDisabled{}}'
    order = 'T.TypeFirst{}' if next(iter(config)) == 'type' else 'T.TypeLast{}'
    if config['type'] == 'json_schema':
        strict = 'T.Prefer{}' if config['strict'] == 'prefer' else 'T.Require{}'
        value = f'T.JsonSchemaSampling{{{strict}, {order}}}'
    else:
        variants = 'G.empty()'
        for key, value in config['variants'].items():
            format_value = 'T.OpenAILark{}' if key == 'openai_lark' else 'T.OpenAIRegex{}'
            variants = f'G.set({variants}, {format_value}, Some{{{text(value)}}})'
        value = f'T.GrammarSampling{{{variants}, {order}}}'
    return f'Some{{T.SamplingConfigured{{{value}}}}}'

def tool_bend(value):
    return 'T.Tool{' + ', '.join([text(value['name']), text(value['description']),
                                bend(value['parameters']), sampling(value['sampling'])]) + '}'

def result(value):
    if 'error' in value:
        error = 'D.OmittedSchema{}' if value['error'] == 'omitted' else 'D.BigIntSchema{}'
        return 'D.Failure{' + error + '}'
    data = value['value']
    actual = 'True{}' if data is True else 'False{}' if data is False else text(data)
    return 'D.Success{' + actual + '}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/src/utils/tool-declaration.bend as D',
          'import ../packages/ai/src/utils/grammar-variants.bend as G',
          'import ../packages/runtime/src/schema-value.bend as V',
          'import ../packages/runtime/src/record.bend as R',
          'import ../packages/runtime/src/f64.bend as F',
          'import ../packages/runtime/src/big-nat.bend as B',
          'import ../packages/ai/test/tool-declaration.bend as H',
          'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, ((left, right), want) in enumerate(zip(cases, expected, strict=True)):
    source.append(f'    H.check({tool_bend(left)}, {tool_bend(right)}, {result(want["left"])}, {result(want["right"])}, {result(want["equal"])}, "declaration {index}")')
source.append(f'    IO.print("PASS {len(cases)} upstream tool-declaration comparisons and serialized snapshots")')
entry = BUILD / 'tool-declaration-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/test-tool-declaration'], cwd=ROOT, check=True)
subprocess.run(['build/test-tool-declaration', '--threads', '1'], cwd=ROOT, check=True, timeout=90)
