"""Compare the composed pure byte decoder with actual _iterSSEMessages.

Check the original iterator's event/data/read timing and the approved raw-only
adaptation's complete events. Host JS is a test oracle, not production logic.
"""
import itertools
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
cases = []
rng = random.Random(6404)


def add(data):
    cases.append([{'bytes': data}])
    cases.append([{'bytes': [byte]} for byte in data] or [{'bytes': []}])
    for cut in range(len(data) + 1):
        cases.append([{'bytes': data[:cut]}, {'null': True}, {'bytes': []}, {'bytes': data[cut:]}])


texts = ['', 'data: x', 'data: x\n', 'data: x\n\n', 'data: x\r', 'data: x\r\r',
         'data: x\r\n', 'data: x\r\n\r\n', 'data: x\r\n\r',
         ': heartbeat\n\ndata: x\n\n', 'event:\n\ndata: x\n\n',
         'data\n\n', 'event: done\n\n', 'event: a\nevent: b\ndata: one\ndata:  two:c\n\n',
         'data: 🌍\n\n', '\ufeffdata: a\n\n\ufeffdata: b\n\n',
         'data: a\rdata: b\n\n', 'data: a\n\r\ndata: b\n\n',
         'data: a\r\rdata: b\r\r', 'data: [DONE]\n\ndata: after\n\n']
for text in texts:
    add(list(text.encode('utf-8')))
for suffix in itertools.product([10, 13, 32, 58], repeat=4):
    add(list(b'data:x') + list(suffix))
for _ in range(100):
    lines = [rng.choice(['data: x', 'data:', 'event:', 'event: a', ': ping', 'id: 1', '']) for _ in range(rng.randrange(1, 12))]
    text = ''.join(line + rng.choice(['\n', '\r', '\r\n']) for line in lines)
    data = list(text.encode())
    cuts = sorted([0, len(data), *[rng.randrange(len(data) + 1) for _ in range(8)]])
    cases.append([{'bytes': data[a:b]} for a, b in zip(cuts, cuts[1:])])
for data in [list(b'data:')+[237,160,128,10,10], list(b'data:')+[239,10,10],
             list(b'data:')+[240,159,146,169,13,10,13,10]]:
    add(data)
cases += [
    [{'text': [100,97,116,97,58,32,55296]}, {'text': [56320,10,10]}],
    [{'text': list(map(ord, 'event:\n\n'))}, {'buffer': list(b'data:x\n\n')}],
    [{'bytes': list(b': ping\n\n')}] * 500 + [{'bytes': list(b'data: final\n\n')}],
]
oracle = r"""
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const url = pathToFileURL(process.argv[1]);
const original = await import(url);
let source = fs.readFileSync(url,'utf8');
const old = 'if (!this.event && !this.data.length)\n                return null;';
if(source.split(old).length !== 2) throw new Error('SDK diagnostic branch changed');
source = source.replace(old, 'if (!this.event && !this.data.length) { this.chunks = []; return null; }');
source = source.replace(/from (["'])(\.[^"']+)\1/g, (_,q,path)=>'from '+q+new URL(path,url).href+q);
const adapted = await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const codes = text=>Array.from(text,c=>c.codePointAt(0)).join(',');
const show = e=>(e.event === null ? 'N' : 'S'+codes(e.event))+'/'+codes(e.data)+'/'+e.raw.map(s=>'['+codes(s)+']').join(';');
async function run(mod, operations) {
  let at = -1;
  const emitted = Array.from({length:operations.length+1},()=>[]);
  async function* input() {
    for(const op of operations) {
      at++;
      yield op.null ? null : op.text ? String.fromCodePoint(...op.text) : op.buffer ? Uint8Array.from(op.buffer).buffer : Uint8Array.from(op.bytes);
    }
    at++;
  }
  const controller = new AbortController();
  for await(const event of mod._iterSSEMessages({body:input()},controller)) emitted[at].push(event);
  if(controller.signal.aborted) throw new Error('normal decoding aborted');
  return emitted;
}
const cases = JSON.parse(fs.readFileSync(0,'utf8'));
const results = [];
for(const operations of cases) {
  const a = await run(original,operations), b = await run(adapted,operations);
  const project = batches=>batches.map(events=>events.map(e=>[e.event,e.data]));
  if(JSON.stringify(project(a)) !== JSON.stringify(project(b))) throw new Error('adaptation changed events or timing');
  results.push(b.map(events=>events.map(show).join('~')).join('|'));
}
console.log(JSON.stringify(results));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, str(SDK / 'core/streaming.mjs')], input=json.dumps(cases), text=True))


def operation(op):
    if 'null' in op:
        return 'n'
    key = 'text' if 'text' in op else 'buffer' if 'buffer' in op else 'bytes'
    return ('t' if key == 'text' else 'b') + ','.join(map(str, op[key]))


arguments = ['s' + '|'.join(map(operation, case)) for case in cases]
subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/sse-stream-runner.bend', 'build/test-sse-stream'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 24):
        actual = subprocess.check_output([str(ROOT / 'build/test-sse-stream'), '--threads', threads, *arguments[start:start+24]], text=True, timeout=30).splitlines()
        wanted = expected[start:start+24]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start+offset], got, want)
    print(f'PASS SSE byte stream: {len(cases)} actual iterator comparisons on {threads} native threads', flush=True)
