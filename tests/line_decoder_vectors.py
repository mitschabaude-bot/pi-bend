"""Compare byte/chunk/flush behavior directly with the pinned OpenAI SDK."""
import itertools
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
rng = random.Random(6401)
cases = []


def lines(chunks):
    cases.append({'operations': [{'bytes': chunk} for chunk in chunks] + [{'flush': True}, {'flush': True}]})


for size in range(7):
    for values in itertools.product([10, 13, 65], repeat=size):
        data = list(values)
        cases.append({'index': data})
        lines([data])
        lines([[byte] for byte in data])
        for cut in range(len(data) + 1):
            lines([data[:cut], [], data[cut:]])
for data in [[239, 187, 191, 65, 10, 239, 187, 191, 66],
             [226, 130, 172, 13, 240, 159, 146, 169, 10],
             [237, 160, 10, 239, 13, 187, 191, 10], [65, 13, 66, 13, 67],
             [226, 130], [239], [239, 187]]:
    for cut in range(len(data) + 1):
        lines([data[:cut], [], data[cut:]])
    lines([[byte] for byte in data])
for _ in range(500):
    data = [rng.choice([10, 13, rng.randrange(256)]) for _ in range(rng.randrange(50))]
    cases.append({'index': data})
    lines([data[:len(data)//2], [], data[len(data)//2:]])
    lines([[byte] for byte in data])
cases += [
    {'operations': [{'bytes': [65, 13]}, {'null': True}, {'bytes': [66]}, {'flush': True}, {'bytes': [67, 10]}, {'flush': True}]},
    {'operations': [{'scalars': [65279, 65, 13]}, {'scalars': [10, 55296, 56320, 10]}, {'scalars': [55296]}, {'flush': True}]},
    {'operations': [{'scalars': [55296]}, {'scalars': [56320, 10]}, {'flush': True}]},
]
oracle = r"""
import fs from 'node:fs';
const {LineDecoder, findDoubleNewlineIndex} = await import(process.argv[1]);
const cases = JSON.parse(fs.readFileSync(0, 'utf8'));
const show = lines => lines.map(s => '['+Array.from(s, c => c.codePointAt(0)).join(',')+']').join(';');
console.log(JSON.stringify(cases.map(c => {
  if (c.index) return String(findDoubleNewlineIndex(Uint8Array.from(c.index)));
  const decoder = new LineDecoder();
  return c.operations.map(op => show(op.flush ? decoder.flush() : decoder.decode(
    op.null ? null : op.scalars ? String.fromCodePoint(...op.scalars) : Uint8Array.from(op.bytes)))).join('|');
})));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, (SDK / 'internal/decoders/line.mjs').as_uri()],
    input=json.dumps(cases), text=True))


def operation(op):
    if 'flush' in op:
        return 'f'
    if 'null' in op:
        return 'n'
    if 'scalars' in op:
        return 't' + ','.join(map(str, op['scalars']))
    return 'b' + ','.join(map(str, op['bytes']))


arguments = [
    'i' + ','.join(map(str, case['index'])) if 'index' in case
    else 'l' + '|'.join(map(operation, case['operations'])) for case in cases
]
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/line-decoder-runner.bend', 'build/test-line-decoder'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 128):
        actual = subprocess.check_output(
            [str(ROOT / 'build/test-line-decoder'), '--threads', threads, *arguments[start:start + 128]], text=True, timeout=30).splitlines()
        wanted = expected[start:start + 128]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start + offset], got, want)
    print(f'PASS line decoder: {len(cases)} SDK comparisons on {threads} native threads', flush=True)
