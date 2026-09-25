"""Compare declaration snapshots/equality directly with pinned pi-mono code."""
from upstream_pin import check_sibling
check_sibling()
import copy
import json
from pathlib import Path
import subprocess
from schema_test_values import string
from tool_test_values import tool_bend
from schema_fixtures import fixtures

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
data = BUILD / 'tool-declaration-input.json'
data.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output([
    'node', 'tests/tool_declaration_reference.mts', str(data)
], cwd=ROOT, text=True))

def result(value):
    if 'error' in value: raise AssertionError(value)
    data = value['value']
    actual = 'True{}' if data is True else 'False{}' if data is False else text(data)
    return 'D.Success{' + actual + '}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/src/utils/tool-declaration.bend as D',
          'import ../packages/ai/test/grammar-variants.bend as G',
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
