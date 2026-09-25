"""Compare complete tool-state changes with the actual upstream implementation."""
import json
from pathlib import Path
import random
import subprocess
from tool_test_values import tool_bend, text
from schema_fixtures import fixtures
from schema_test_values import valid

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
schemas = [fixture['input'] for fixture in fixtures(ROOT)]

def tool(name, description=None, schema=None):
    return dict(name=name, description=description or name + ' tool',
                parameters=schemas[0] if schema is None else schema, sampling=None)

# Original getToolStateChanges assertions from system-message-replay.test.ts.
cases = [([tool('a'), tool('b')], [tool('b', 'changed'), tool('c')]),
         ([tool('a')], [tool('a')])]
cases += [([], []), ([], [tool('a'), tool('a')]),
          ([tool('a'), tool('a')], []),
          ([tool('a', 'old'), tool('a', 'new')], [tool('a', 'new')]),
          ([tool('a', 'old')], [tool('a', 'new'), tool('a', 'old')]),
          ([tool('10'), tool('2')], [tool('2', 'changed'), tool('10', 'changed')])]
rng = random.Random(851150)
for _ in range(64):
    states = []
    for _ in range(2):
        state = []
        for _ in range(rng.randrange(6)):
            name = rng.choice(['a', 'b', '0', '10', '__proto__'])
            state.append(tool(name, rng.choice(['old', 'new']), rng.choice([schemas[0], schemas[1], schemas[6]])))
        states.append(state)
    cases.append(states)
data = BUILD / 'tool-state-input.json'
data.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output([
    'node', 'tests/tool_declaration_reference.mts', str(data), 'state'
], cwd=ROOT, text=True))

def items(values, encode):
    return ' <> '.join([encode(value) for value in values] + ['Nil{}'])

def result(value):
    if 'error' in value: raise AssertionError(value)
    changes = value['value']
    return 'D.Success{H.ExpectedChanges{' + items(changes['toolsAdded'], text) + ', ' + items(changes['toolsRemoved'], text) + '}}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/src/utils/tool-declaration.bend as D',
          'import ../packages/runtime/src/schema-value.bend as V',
          'import ../packages/runtime/src/record.bend as R',
          'import ../packages/runtime/src/f64.bend as F',
          'import ../packages/runtime/src/big-nat.bend as B',
          'import ../packages/ai/test/tool-state.bend as H',
          'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, ((previous, current), want) in enumerate(zip(cases, expected, strict=True)):
    source.append(f'    H.check({items(previous, tool_bend)}, {items(current, tool_bend)}, {result(want)}, "tool state {index}")')
source.append(f'    IO.print("PASS {len(cases)} upstream tool-state change cases")')
entry = BUILD / 'tool-state-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), 'build/test-tool-state'], cwd=ROOT, check=True)
subprocess.run(['build/test-tool-state', '--threads', '1'], cwd=ROOT, check=True, timeout=90)
