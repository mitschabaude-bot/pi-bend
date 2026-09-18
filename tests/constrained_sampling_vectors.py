"""Check typed sampling-config JSON against JavaScript object semantics."""
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

oracle = '''const cases=JSON.parse(process.argv[1]);
const names=['openai_lark','openai_regex'];
console.log(JSON.stringify(cases.map(([kind,ops,order])=>{
  if(kind===false) return {text:JSON.stringify(false),state:[]};
  const variants={};
  for(const [op,i,value] of ops) {
    if(op==='remove') delete variants[names[i]];
    else variants[names[i]]=value===null ? undefined : value;
  }
  const key=kind==='grammar' ? 'variants' : 'strict';
  const value=kind==='grammar' ? variants : kind;
  const type=kind==='grammar' ? 'grammar' : 'json_schema';
  const config=order===0 ? {type,[key]:value} : {[key]:value,type};
  return {text:JSON.stringify(config),state:names.map(k=>
    !Object.hasOwn(variants,k) ? ['absent'] : variants[k]===undefined ? ['undefined'] : ['value',variants[k]])};
})));'''
expected = json.loads(subprocess.check_output(['node', '-e', oracle, json.dumps(cases)], text=True))

def string(text):
    result = 'SNil{}'
    for point in reversed(list(map(ord, text))):
        result = f'SCon{{Chr{{{point}}}, {result}}}'
    return result

def fmt(index):
    return 'T.OpenAILark{}' if index == 0 else 'T.OpenAIRegex{}'

source = ['import Base', 'import ../packages/ai/src/types.bend as T',
          'import ../packages/ai/src/utils/grammar-variants.bend as G',
          'import ../packages/ai/src/utils/constrained-sampling-json.bend as C',
          'import ../packages/ai/src/utils/json.bend as J',
          'def check(actual: Maybe<&2, String>, expected: String) -> IO(Unit):',
          '  match actual:',
          '    case Some{value}: Bool.pick(IO(Unit), String.eq(value, expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "sampling JSON differs"))',
          '    case None{}: IO.die(Unit, 1, "JSON codec failed")',
          'def state(actual: Maybe<&2, Maybe<&2, String>>, expected: Maybe<&2, Maybe<&2, String>>) -> Bool:',
          '  match actual expected:',
          '    case None{} None{}: True{}',
          '    case Some{None{}} Some{None{}}: True{}',
          '    case Some{Some{a}} Some{Some{b}}: String.eq(a, b)',
          '    case _ _: False{}',
          'def checkState(actual: Maybe<&2, Maybe<&2, String>>, expected: Maybe<&2, Maybe<&2, String>>) -> IO(Unit):',
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
            want = 'None{}' if entry[0] == 'absent' else 'Some{None{}}' if entry[0] == 'undefined' else 'Some{Some{' + string(entry[1]) + '}}'
            source.append(f'    checkState(G.get(v{i}, {fmt(index)}), {want})')
    order_bend = 'T.TypeFirst{}' if order == 0 else 'T.TypeLast{}'
    if kind is False:
        value = 'T.SamplingDisabled{}'
    elif kind == 'grammar':
        value = f'T.SamplingConfigured{{T.GrammarSampling{{v{i}, {order_bend}}}}}'
    else:
        strict = 'T.Prefer{}' if kind == 'prefer' else 'T.Require{}'
        value = f'T.SamplingConfigured{{T.JsonSchemaSampling{{{strict}, {order_bend}}}}}'
    source.append(f'    check(J.stringify(C.toJson({value})), {string(result["text"])})')
source.append(f'    IO.print("PASS {len(cases)} constrained-sampling JSON and grammar-property cases")')
entry = BUILD / 'constrained-sampling-vectors.bend'
entry.write_text('\n'.join(source) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(entry), 'build/test-constrained-sampling'], cwd=ROOT, check=True)
subprocess.run(['build/test-constrained-sampling', '--threads', '1'], cwd=ROOT, check=True, timeout=60)
