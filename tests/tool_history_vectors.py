"""Check immutable tool history against upstream transcript functions."""
import json
from pathlib import Path
import random
import subprocess
from tool_test_values import tool_bend
from schema_fixtures import fixtures
from schema_test_values import valid

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
schema = fixtures(ROOT)[0]['input']

def tool(name='a', description='a tool', parameters=None):
    return dict(name=name, description=description, parameters=schema if parameters is None else parameters, sampling=None)

def system(added, removed=None):
    return ['system', added, removed or []]

cases = [([], []), ([tool()], [system([0])]),
         ([tool()], [system([0, 0])]),
         ([tool(), tool(description='changed')], [system([0]), system([1])]),
         ([tool(), tool(description='changed')], [system([0]), system([], ['a']), system([1])]),
         ([tool()], [system([0]), system([], ['a']), system([0])]),
         ([tool(), tool(description='changed')], [['user', [0], []], system([1])])]
rng = random.Random(851183)
for _ in range(48):
    pool = [tool(rng.choice(['a', 'b', '10', '0']), rng.choice(['old', 'new'])) for _ in range(4)]
    entries = [[rng.choice(['system', 'system', 'user']), [rng.randrange(4) for _ in range(rng.randrange(4))],
                [rng.choice(['a', 'b'])] if rng.randrange(4) == 0 else []] for _ in range(rng.randrange(5))]
    cases.append([pool, entries])
path = BUILD / 'tool-history-input.json'
path.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output([
    'node', 'tests/tool_declaration_reference.mts', str(path), 'history'
], cwd=ROOT, text=True))

def boolean(value):
    return 'True{}' if value else 'False{}'

def result(value):
    if 'error' in value: raise AssertionError(value)
    return 'D.Success{' + boolean(value['value']) + '}'

def items(values):
    return ' <> '.join(values + ['Nil{}'])

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/src/utils/transcript.bend as Transcript',
          'import ../packages/ai/src/utils/tool-declaration.bend as D',
          'import ../packages/runtime/src/schema-value.bend as V',
          'import ../packages/runtime/src/record.bend as R',
          'import ../packages/runtime/src/f64.bend as F',
          'import ../packages/runtime/src/big-nat.bend as B',
          'import ../packages/runtime/src/ref.bend as Ref',
          'import ../packages/ai/test/tool-declaration.bend as H',
          'def main() -> IO(Unit):', '  do IO<Unit>:']
for case, ((pool, entries), want) in enumerate(zip(cases, expected, strict=True)):
    for index, value in enumerate(pool):
        source.append(f'    +t{case}_{index} : T.Tool<V.Value> <- IO.pure(T.Tool<V.Value>, {tool_bend(value)})')
    messages = []
    for index, (role, added, removed) in enumerate(entries):
        name = f'm{case}_{index}'
        if role == 'system':
            references = items([f't{case}_{key}' for key in added])
            removals = items(['T.ToolReference{' + json.dumps(key) + '}' for key in removed])
            source.append(f'    +{name} : T.SystemMessage<V.Value> <- IO.pure(T.SystemMessage<V.Value>, T.SystemMessage{{T.SystemText{{""}}, None{{}}, Some{{{references}}}, Some{{{removals}}}, F.fromU32(0)}})')
            messages.append(f'T.System{{{name}}}')
        else:
            source.append(f'    +{name} : T.UserMessage <- IO.pure(T.UserMessage, T.UserMessage{{T.UserText{{"ignored"}}, F.fromU32(0)}})')
            messages.append(f'T.User{{{name}}}')
    source.append(f'    +messages{case} : List<&2, T.Message<V.Value, Unit, Unit, Unit>> = {items(messages)}')
    source.append(f'    nonAdditive : Bool = Transcript.hasNonAdditiveToolChanges(V.Value, Unit, Unit, Unit, messages{case})')
    source.append(f'    H.assertion(Bool.not(Bool.xor(nonAdditive, {boolean(want["nonAdditive"])})), "non-additive history {case}")')
    source.append(f'    redefined : D.DeclarationResult<Bool> = Transcript.hasToolRedefinitions(Unit, Unit, Unit, messages{case})')
    source.append(f'    H.assertion(H.sameBool(redefined, {result(want["redefined"])}), "redefinition history {case}")')
source.append(f'    IO.print("PASS {len(cases)} upstream tool histories with immutable values")')
entry = BUILD / 'tool-history-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), 'build/test-tool-history'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run(['build/test-tool-history', '--threads', threads], cwd=ROOT, check=True, timeout=90)
