"""Exercise exact pinned SDK chunk framing and the input read that emits it."""
import itertools
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
cases = []
rng = random.Random(6402)


def add(chunks):
    cases.append([{'bytes': chunk} for chunk in chunks])


for size in range(7):
    for data in itertools.product([10, 13, 65], repeat=size):
        data = list(data)
        add([data])
        add([[byte] for byte in data] or [[]])
        for cut in range(len(data) + 1):
            add([data[:cut], [], data[cut:]])
for _ in range(500):
    data = [rng.choice([10, 13, rng.randrange(256)]) for _ in range(rng.randrange(80))]
    add([[byte] for byte in data] or [[]])
    cut = rng.randrange(len(data) + 1)
    add([data[:cut], [], data[cut:]])
cases += [
    [{'bytes': [13]}, {'null': True}, {'bytes': [10]}, {'bytes': [13]}, {'null': True}, {'bytes': [10]}],
    [{'text': [65279, 100, 97, 116, 97, 58, 32, 55296, 10]}, {'text': [56320, 10, 10]}],
    [{'null': True}],
]
oracle = r"""
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const root = process.argv[1];
const {encodeUTF8} = await import(pathToFileURL(root+'/internal/utils/bytes.mjs'));
const {findDoubleNewlineIndex} = await import(pathToFileURL(root+'/internal/decoders/line.mjs'));
const source = fs.readFileSync(root+'/core/streaming.mjs', 'utf8');
const begin = source.indexOf('async function* iterSSEChunks(');
const end = source.indexOf('\nclass SSEDecoder', begin);
if (begin < 0 || end < 0) throw new Error('SDK private framing function not found');
// Expose the exact private function for tests, with its real SDK dependencies.
const iterator = new Function('encodeUTF8','findDoubleNewlineIndex',
  source.slice(begin,end)+'\nreturn iterSSEChunks;')(encodeUTF8,findDoubleNewlineIndex);
const cases = JSON.parse(fs.readFileSync(0,'utf8'));
const results = [];
for (const operations of cases) {
  const emitted = Array.from({length:operations.length+1},()=>[]);
  let index = -1;
  async function* input() {
    for (const op of operations) {
      index++;
      yield op.null ? null : op.text ? String.fromCodePoint(...op.text) : Uint8Array.from(op.bytes);
    }
    index++;
  }
  for await (const chunk of iterator(input())) emitted[index].push('['+Array.from(chunk).join(',')+']');
  results.push(emitted.map(chunks=>chunks.join(';')).join('|'));
}
console.log(JSON.stringify(results));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, str(SDK)], input=json.dumps(cases), text=True))


def operation(op):
    if 'null' in op:
        return 'n'
    key = 'text' if 'text' in op else 'bytes'
    return ('t' if key == 'text' else 'b') + ','.join(map(str, op[key]))


arguments = ['s' + '|'.join(map(operation, case)) for case in cases]
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/sse-chunks-runner.bend', 'build/test-sse-chunks'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 64):
        actual = subprocess.check_output(
            [str(ROOT / 'build/test-sse-chunks'), '--threads', threads, *arguments[start:start + 64]], text=True, timeout=30).splitlines()
        wanted = expected[start:start + 64]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start + offset], got, want)
    print(f'PASS SSE chunks: {len(cases)} SDK comparisons on {threads} native threads', flush=True)
