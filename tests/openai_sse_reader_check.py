"""Compare composed JSON reader effects with actual SDK Stream.fromSSEResponse.

Error text is normalized; APIError formatting and response acquisition are separate.
"""
import itertools
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
scripts = [
    [], [''], ['data: "a"\n\n'], ['data: "a"\n\ndata: "b"\n\n'],
    ['data: "a"'], ['data: "a"\r\n\r'], [None, '', 'data: "a"\n\n', 'data: "b"\n\n'],
    [{'error': True}], [{'abort': True}], ['data: "a"\n\n', {'error': True}],
    ['data: "a"\n\n', {'abort': True}], ['data: [DONE]\n\n', {'error': True}],
    ['data: [DONE]\n\n', {'abort': True}], ['data: [DONE]suffix\n\ndata: {\n\n'],
    ['data: {\n\n'], ['event: thread.run\ndata: {\n\n'],
    ['data: {"error":"bad"}\n\n'], ['data: "a"\n\ndata: {\n\n'],
    ['event: thread.run\ndata: "a"\n\n'], ['event:\ndata: "a"\n\n'],
    ['data: [DONE]\n\n', 'data: "a"\n\n', 'data: [DONE]\n\n'],
]
cases = []
for chunks in scripts:
    for size in range(4):
        for actions in itertools.product('nr', repeat=size):
            for close_mode in range(3):
                for diagnostic_mode in range(3):
                    for synthesize in [False, True]:
                        cases.append({'chunks': chunks, 'actions': ''.join(actions) + 'r', 'closeMode': close_mode, 'diagnosticMode': diagnostic_mode, 'synthesize': synthesize})
oracle = r"""
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const {Stream} = await import(pathToFileURL(process.argv[1]));
const cases = JSON.parse(fs.readFileSync(0,'utf8'));
const show = v=>typeof v==='string'?v:'event:'+(v.event===null?'absent':v.event)+':'+v.data;
const aborted=()=>Object.assign(new Error('cancelled'),{name:'AbortError'});
const errorText=e=>e instanceof SyntaxError?'json':e.constructor.name==='APIError'?'api':e.message;
const saved=console.error;
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
      if(chunk?.abort) throw aborted();
      return {done:false,value:Array.isArray(chunk) ? Uint8Array.from(chunk) : chunk};
    },
    async return() {
      trace.push('close');
      if(test.closeMode===1) throw new Error('close failed');
      if(test.closeMode===2) throw aborted();
      return {done:true};
    }
  };
  const diagnostic=target=>(...args)=>{
    if(args[0]!=='Could not parse message into JSON:') return;
    trace.push('diagnostic:'+target);
    if(test.diagnosticMode===1) throw new Error('diagnostic failed');
    if(test.diagnosticMode===2) throw aborted();
  };
  console.error=diagnostic('console');
  const client={logLevel:'error',logger:{error:diagnostic('client')}};
  const controller={abort(){trace.push('abort');}};
  const iterator = Stream.fromSSEResponse({body:input,headers:new Headers()},controller,client,test.synthesize)[Symbol.asyncIterator]();
  for(const action of test.actions) {
    if(action === 'n') {
      try { const r = await iterator.next(); trace.push('next:'+(r.done ? '-' : show(r.value))); }
      catch(e) { trace.push('next:error:'+errorText(e)); }
    } else {
      try { await iterator.return(); trace.push('return:ok'); }
      catch(e) { trace.push('return:error:'+errorText(e)); }
    }
  }
  results.push(trace.join('|'));
}
console.error=saved;
console.log(JSON.stringify(results));
"""
expected = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', oracle, str(SDK / 'core/streaming.mjs')], input=json.dumps(cases), text=True))


def chunk(value):
    if value is None:
        return 'n'
    if isinstance(value, dict):
        return 'a' if value.get('abort') else 'e'
    if isinstance(value, str):
        return 't' + ','.join(str(ord(c)) for c in value)
    return 'b' + ','.join(map(str, value))


arguments = ['s' + '/'.join([str(case['closeMode']), str(case['diagnosticMode']), str(int(case['synthesize'])), case['actions'], '|'.join(map(chunk, case['chunks']))]) for case in cases]
(ROOT / 'build').mkdir(exist_ok=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/ai/test/openai-sse-reader-runner.bend', 'build/test-openai-sse-reader'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 32):
        actual = subprocess.check_output([str(ROOT / 'build/test-openai-sse-reader'), '--threads', threads, *arguments[start:start+32]], text=True, timeout=30).splitlines()
        wanted = expected[start:start+32]
        assert len(actual) == len(wanted), (start, len(actual), len(wanted))
        for offset, (got, want) in enumerate(zip(actual, wanted)):
            assert got == want, (threads, cases[start+offset], got, want)
    print(f'PASS SSE JSON reader: {len(cases)} SDK next/return traces on {threads} native threads', flush=True)
