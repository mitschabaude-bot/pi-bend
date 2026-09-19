"""Compare SDK SSE fields and the user-approved diagnostic-only adaptation."""
import itertools
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
rng = random.Random(6403)
fields = ['', ': heartbeat', 'event:', 'event: message', 'data:', 'data: one', 'id: 1']
cases = [list(lines) for length in range(1, 5) for lines in itertools.product(fields, repeat=length)]
cases += [
    [': first', '', 'unknown: x', '', 'event:', '', 'data: kept', ''],
    ['event: first', 'event: second', 'data: a', 'data:  b:c', 'data:\ttab', ''],
    ['data', '', 'data:', '', 'event', '', 'data: next', ''],
    ['data: a\r', '\r', 'data: b\r\r', '', 'Data: ignored', ''],
    ['data: 🌍', 'data: \ud800', '', 'event: 🌍', ''],
    [': heartbeat', ''] * 1000 + ['data: final', ''],
]
alphabet = ['data: z', 'event: x', 'event:', ': comment', 'retry: 5', ' data: no', 'data : no', '', '\r', 'data: \r']
for _ in range(500):
    cases.append([rng.choice(alphabet) for _ in range(rng.randrange(1, 40))])
oracle = r"""
import fs from 'node:fs';
const source = fs.readFileSync(process.argv[1], 'utf8');
const begin = source.indexOf('class SSEDecoder {');
if (begin < 0) throw new Error('SDK class not found');
const body = source.slice(begin);
const old = 'if (!this.event && !this.data.length)\n                return null;';
if (body.split(old).length !== 2) throw new Error('SDK blank-block branch changed');
const Original = new Function(body+'\nreturn SSEDecoder;')();
const Adapted = new Function(body.replace(old,
  'if (!this.event && !this.data.length) { this.chunks = []; return null; }')+'\nreturn SSEDecoder;')();
const codes = text => Array.from(text, c=>c.codePointAt(0)).join(',');
const show = event => event === null ? '-' :
  (event.event === null ? 'N' : 'S'+codes(event.event))+'/'+codes(event.data)+'/'+event.raw.map(s=>'['+codes(s)+']').join(';');
const cases = JSON.parse(fs.readFileSync(0,'utf8'));
const results = cases.map(lines=>{
  const original = new Original(), adapted = new Adapted();
  return lines.map(line=>{
    const a = original.decode(line), b = adapted.decode(line);
    if ((a === null) !== (b === null) || (a && (a.event !== b.event || a.data !== b.data)))
      throw new Error('diagnostic adaptation changed events');
    return show(b);
  }).join('|');
});
console.log(JSON.stringify(results));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, str(SDK / 'core/streaming.mjs')],
    input=json.dumps(cases), text=True))
arguments = ['s' + '|'.join(','.join(str(ord(char)) for char in line) for line in lines) for lines in cases]
subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/sse-decoder-runner.bend', 'build/test-sse-decoder'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 32):
        actual = subprocess.check_output([str(ROOT / 'build/test-sse-decoder'), '--threads', threads, *arguments[start:start+32]], text=True, timeout=30).splitlines()
        wanted = expected[start:start+32]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start+offset], got, want)
    print(f'PASS SSE decoder: {len(cases)} SDK/adaptation sequences on {threads} native threads', flush=True)
