"""Compare pull/return traces with the SDK's actual async SSE generator."""
import itertools
import json
import os
from pathlib import Path
from bend_toolchain import BEND
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
scripts = [
    [], [''], ['data: a\n\n'], ['data: a\n\ndata: b\n\n'],
    ['data: a'], ['data: a\n'], ['data: a\r\n\r'],
    [None, '', 'data: a\n\n', 'data: b\n\n'],
    [{'error': True}], ['data: a\n\n', {'error': True}],
    ['data: a\n', {'error': True}], ['data', ': a\n', '\n'],
    [list(b'data: a\n\ndata: b\n\n'), {'error': True}],
]
cases = []
for chunks in scripts:
    for size in range(5):
        for actions in itertools.product('nr', repeat=size):
            for close_fails in [False, True]:
                cases.append({'chunks': chunks, 'actions': ''.join(actions) + 'r', 'closeFails': close_fails})
oracle = r"""
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const {_iterSSEMessages} = await import(pathToFileURL(process.argv[1]));
const cases = JSON.parse(fs.readFileSync(0,'utf8'));
const codes = s=>Array.from(s,c=>c.codePointAt(0)).join(',');
const show = e=>(e.event === null ? 'N' : 'S'+codes(e.event))+'/'+codes(e.data)+'/'+e.raw.map(s=>'['+codes(s)+']').join(';');
const results = [];
for(const test of cases) {
  const trace = [];
  let at = 0;
  const input = {
    [Symbol.asyncIterator]() { return this; },
    async next() {
      trace.push('read');
      if(at === test.chunks.length) return {done:true};
      const chunk = test.chunks[at++];
      if(chunk?.error) throw new Error('read failed');
      return {done:false,value:Array.isArray(chunk) ? Uint8Array.from(chunk) : chunk};
    },
    async return() {
      trace.push('close');
      if(test.closeFails) throw new Error('close failed');
      return {done:true};
    }
  };
  const iterator = _iterSSEMessages({body:input},new AbortController());
  for(const action of test.actions) {
    if(action === 'n') {
      try { const r = await iterator.next(); trace.push('next:'+(r.done ? '-' : show(r.value))); }
      catch(e) { trace.push('next:error:'+e.message); }
    } else {
      try { await iterator.return(); trace.push('return:ok'); }
      catch(e) { trace.push('return:error:'+e.message); }
    }
  }
  results.push(trace.join('|'));
}
console.log(JSON.stringify(results));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, str(SDK / 'core/streaming.mjs')], input=json.dumps(cases), text=True))


def chunk(value):
    if value is None:
        return 'n'
    if isinstance(value, dict):
        return 'e'
    if isinstance(value, str):
        return 't' + ','.join(str(ord(c)) for c in value)
    return 'b' + ','.join(map(str, value))


arguments = ['s' + str(int(case['closeFails'])) + '/' + case['actions'] + '/' + '|'.join(map(chunk, case['chunks'])) for case in cases]
(ROOT / 'build').mkdir(exist_ok=True)
negative = ROOT / 'build/sse-reader-duplicate.bend'
negative.write_text('import Base\nimport ../packages/runtime/src/sse.bend as Reader\n'
                    'def duplicate(+cursor: Reader.Cursor<String>) -> Reader.Cursor<String> & Reader.Cursor<String>:\n'
                    '  (cursor, cursor)\n')
rejected = subprocess.run([BEND, str(negative)],
                          cwd=ROOT, text=True, capture_output=True, timeout=30)
diagnostic = rejected.stdout + rejected.stderr
assert rejected.returncode != 0 and 'expected : Data' in diagnostic and 'observed : Type' in diagnostic, diagnostic
print('PASS SSE cursor duplication rejected by the type checker', flush=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/sse-reader-runner.bend', 'build/test-sse-reader'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 32):
        actual = subprocess.check_output([str(ROOT / 'build/test-sse-reader'), '--threads', threads, *arguments[start:start+32]], text=True, timeout=30).splitlines()
        wanted = expected[start:start+32]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start+offset], got, want)
    print(f'PASS SSE reader: {len(cases)} SDK next/return traces on {threads} native threads', flush=True)
