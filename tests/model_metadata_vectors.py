"""Differential model thinking tests using the actual upstream helper bodies."""
from upstream_pin import check_sibling
check_sibling()
import json
from pathlib import Path
import random
import subprocess
from tool_test_values import text

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
levels = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']
cases = [[False, None], [True, None], [True, []], [False, [[key, None] for key in levels]]]
for mask in range(128):
    cases.append([True, [[key, None if mask & (1 << index) else ''] for index, key in enumerate(levels)]])
rng = random.Random(851930)
for _ in range(80):
    entries = [[key, rng.choice([None, '__undefined__', '', 'custom'])] for key in levels if rng.randrange(4) != 0]
    rng.shuffle(entries)
    cases.append([rng.randrange(5) != 0, entries])
path = BUILD / 'model-metadata-input.json'
path.write_text(json.dumps(cases))
expected = json.loads(subprocess.check_output(['node', 'tests/model_metadata_reference.mts', str(path)], cwd=ROOT, text=True))

def level(name):
    return 'T.Off{}' if name == 'off' else 'T.Thinking{T.' + {'minimal': 'Minimal', 'low': 'Low', 'medium': 'Medium', 'high': 'High', 'xhigh': 'XHigh', 'max': 'Max'}[name] + '{}}'

def items(values):
    return ' <> '.join(values + ['Nil{}'])

def mapping(entries):
    if entries is None:
        return 'None{}'
    properties = []
    for key, value in entries:
        mapped = 'None{}' if value == '__undefined__' else 'Some{T.NullValue{}}' if value is None else 'Some{T.PresentValue{' + text(value) + '}}'
        properties.append('T.ThinkingLevelMapping{' + level(key) + ', ' + mapped + '}')
    return 'Some{T.ThinkingLevelMap{' + items(properties) + '}}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/test/model-thinking.bend as H',
          'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, ((reasoning, entries), want) in enumerate(zip(cases, expected, strict=True)):
    value = 'H.model("test", "Test", ' + ('True{}' if reasoning else 'False{}') + ', ' + mapping(entries) + ')'
    source.append(f'    H.check({value}, {items([text(v) for v in want["levels"]])}, {items([text(v) for v in want["clamped"]])}, "model thinking {index}")')

identities = ['__undefined__', None,
    dict(id='a', provider='p', api='openai-completions'),
    dict(id='a', provider='p', api='openai-responses'),
    dict(id='b', provider='p', api='openai-completions'),
    dict(id='a', provider='q', api='openai-completions'),
    dict(id='😀', provider='p', api='custom-😀'),
    dict(id='\ud83d\ude00', provider='p', api='custom-\ud83d\ude00')]
api_checks = [[i, query] for i in range(2, len(identities)) for query in ('openai-completions', 'openai-responses', 'custom-😀', 'custom-\ud83d\ude00', 'unknown')]
identity_path = BUILD / 'model-identity-input.json'
identity_path.write_text(json.dumps(dict(models=identities, apiChecks=api_checks)))
identity_expected = json.loads(subprocess.check_output(['node', 'tests/model_metadata_reference.mts', str(identity_path), 'identity'], cwd=ROOT, text=True))
source.insert(2, 'import ../packages/ai/src/models.bend as M')
source.insert(3, 'import ../packages/ai/src/utils/model-api.bend as Api')
for index, value in enumerate(identities):
    if isinstance(value, dict):
        source.append(f'    +identity{index} : T.Model<Unit> = H.identityModel({text(value["id"])}, {text(value["provider"])}, Api.fromString({text(value["api"])}))')
def optional(index):
    return 'None{}' if identities[index] == '__undefined__' else 'Some{T.NullValue{}}' if identities[index] is None else f'Some{{T.PresentValue{{identity{index}}}}}'
for a in range(len(identities)):
    for b in range(len(identities)):
        want = 'True{}' if identity_expected['equal'][a * len(identities) + b] else 'False{}'
        source.append(f'    H.assertion(Bool.not(Bool.xor(M.modelsAreEqual(Unit, {optional(a)}, {optional(b)}), {want})), "model identity {a}/{b}")')
for index, ((item, query), expected_api) in enumerate(zip(api_checks, identity_expected['api'], strict=True)):
    want = 'True{}' if expected_api else 'False{}'
    source.append(f'    H.assertion(Bool.not(Bool.xor(M.hasApi(Unit, identity{item}, {text(query)}), {want})), "model API predicate {index}")')
source.append('    IO.print("PASS 64 model identity pairs and 30 API predicates against upstream")')

source.append(f'    IO.print("PASS {len(cases)} upstream thinking configurations and all seven clamp inputs")')
entry = BUILD / 'model-metadata-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/test-model-metadata'], cwd=ROOT, check=True)
subprocess.run(['build/test-model-metadata', '--threads', '1'], cwd=ROOT, check=True, timeout=90)
subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/ai/test/model-thinking.bend', 'build/test-model-thinking'], cwd=ROOT, check=True)
subprocess.run(['build/test-model-thinking', '--threads', '1'], cwd=ROOT, check=True, timeout=30)
