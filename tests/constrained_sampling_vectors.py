"""Check typed sampling-config JSON with a native optional-field model."""
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
rng = random.Random(851526)
formats = ['openai_lark', 'openai_regex']
cases = [[False, [], 0]]
for order in (0, 1):
    for strict in ('prefer', 'require'):
        cases.append([strict, [], order])
    for ops in ([], [['set', 0, 'start: "x"'], ['set', 1, 'x+']],
                [['set', 1, 'x+'], ['set', 0, 'start: "x"']],
                [['set', 0, None], ['set', 1, 'x'], ['set', 0, 'later']],
                [['set', 0, 'first'], ['set', 1, 'x'], ['remove', 0, None], ['set', 0, 'last']]):
        cases.append(['grammar', ops, order])
for _ in range(100):
    ops = [[rng.choice(['set', 'set', 'remove']), rng.randrange(2),
            rng.choice([None, '', '"\\\n', 'a+', 'λ', 'start: "x"'])]
           for _ in range(rng.randrange(1, 24))]
    cases.append(['grammar', ops, rng.randrange(2)])

expected = []
for kind, ops, _ in cases:
    variants = [None, None]
    for op, index, value in ops:
        variants[index] = None if op == 'remove' else value
    config = False if kind is False else ({'type': 'grammar', 'variants': {k:v for k,v in zip(formats,variants) if v is not None}} if kind == 'grammar' else {'type':'json_schema','strict':kind})
    expected.append({'text':json.dumps(config,ensure_ascii=False,separators=(',',':')), 'state':variants})

def string(text):
    result = 'SNil{}'
    for point in reversed(list(map(ord, text))):
        result = f'SCon{{Chr{{{point}}}, {result}}}'
    return result

def fmt(index):
    return 'T.OpenAILark{}' if index == 0 else 'T.OpenAIRegex{}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/test/grammar-variants.bend as G',
          'import ../packages/ai/src/utils/tool-declaration.bend as C',
          'import ../packages/ai/src/utils/json.bend as J',
          'def check(actual: Maybe<&2, String>, expected: String) -> IO(Unit):',
          '  match actual:',
          '    case Some{value}: Bool.pick(IO(Unit), String.eq(value, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "sampling JSON differs"))',
          '    case None{}: IO.die(Unit, 1, "JSON codec failed")',
          'def state(actual: Maybe<&2, String>, expected: Maybe<&2, String>) -> Bool:',
          '  match actual expected:',
          '    case None{} None{}: True{}',
          '    case Some{a} Some{b}: String.eq(a, b)',
          '    case _ _: False{}',
          'def checkState(actual: Maybe<&2, String>, expected: Maybe<&2, String>) -> IO(Unit):',
          '  Bool.pick(IO(Unit), state(actual, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "grammar property state differs"))',
          'def main() -> IO(Unit):', '  do IO<Unit>:']
for i, ((kind, ops, order), result) in enumerate(zip(cases, expected, strict=True)):
    variants = 'G.empty()'
    for op, index, value in ops:
        variants = (f'G.remove({variants}, {fmt(index)})' if op == 'remove' else
                    f'G.set({variants}, {fmt(index)}, ' + ('None{}' if value is None else 'Some{' + string(value) + '}') + ')')
    if kind == 'grammar':
        source.append(f'    +v{i} : T.GrammarVariants = {variants}')
        for index, entry in enumerate(result['state']):
            want = 'None{}' if entry is None else 'Some{' + string(entry) + '}'
            source.append(f'    checkState(G.get(v{i}, {fmt(index)}), {want})')
    if kind is False:
        value = 'T.SamplingDisabled{}'
    elif kind == 'grammar':
        value = f'T.SamplingConfigured{{T.GrammarSampling{{v{i}}}}}'
    else:
        strict = 'T.Prefer{}' if kind == 'prefer' else 'T.Require{}'
        value = f'T.SamplingConfigured{{T.JsonSchemaSampling{{{strict}}}}}'
    source.append(f'    check(J.stringify(C.samplingToJson({value})), {string(result["text"])})')
source.append(f'    IO.print("PASS {len(cases)} constrained-sampling JSON and grammar-property cases")')
entry = BUILD / 'constrained-sampling-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), 'build/test-constrained-sampling'], cwd=ROOT, check=True)
subprocess.run(['build/test-constrained-sampling', '--threads', '1'], cwd=ROOT, check=True, timeout=60)
