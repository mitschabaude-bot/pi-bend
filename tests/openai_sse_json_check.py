"""Pure dispatch parity with openai 6.40.0's real Stream.fromSSEResponse.

Does not claim IO abort/consumption parity or APIError formatting parity.
Syntax errors compare categories and retained diagnostic context, not engine text.
"""
import itertools
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK / 'package.json').read_text())['version'] == '6.40.0'
values = ['null', 'false', 'true', '0', '-0', '12.5', '""', '"🌍"', '[]', '{}',
          '[1,null,{"x":true}]', '{"response":{"id":"r"}}', '[DONE]', '[DONE]suffix',
          ' [DONE]', '', '{', 'undefined', '[1,]', '{"x":}', 'true false']
for error in ['null', 'false', '0', '-0', '1e-999', '""', 'true', '1', '-1', '1e999',
              '"failure"', '[]', '{}', '{"message":"bad","code":"invalid"}']:
    values.append('{"error":' + error + ',"data":"kept"}')
cases = list(itertools.product([False, True], [False, True], [None, '', 'message', 'error', 'thread', 'thread.', 'thread.run.failed', 'Thread.run'], values))
oracle = r'''
import fs from 'node:fs';
const {Stream} = await import(process.argv[1]);
const cases = JSON.parse(fs.readFileSync(0, 'utf8'));
const codes = s => Array.from(s,c=>c.codePointAt(0)).join(',');
const results = [];
const serialize = v => JSON.stringify(v,(_,x)=>x===Infinity?'__positive_infinity__':x).replaceAll('"__positive_infinity__"','1e999');
const saved = console.error;
for (const [done,synthesize,event,data] of cases) {
  const logs=[];
  console.error=(...args)=>logs.push(['console',args]);
  const client={logLevel:'error',logger:{error:(...args)=>logs.push(['client',args])}};
  const frame=(event===null?'':'event: '+event+'\n')+'data: '+data+'\n\n';
  const response=new Response((done?'data: [DONE]\n\n':'')+frame);
  let output=[];
  try {
    for await (const value of Stream.fromSSEResponse(response,new AbortController(),client,synthesize)) {
      output.push((synthesize || event?.startsWith('thread.')) ?
        'event/'+(value.event===null?'N':'S'+codes(value.event))+'/'+serialize(value.data) :
        'json/'+serialize(value));
    }
    if(output.length>1) throw new Error('unexpected extra value');
    results.push(output[0]??'done');
  } catch(error) {
    if(error instanceof SyntaxError) {
      if(logs.length!==2 || logs[0][1][1]!==data || JSON.stringify(logs[1][1][1])!==JSON.stringify(frame.slice(0,-2).split('\n')))
        throw new Error('unexpected diagnostic context '+JSON.stringify(logs));
      results.push('invalid/'+logs[0][0]+'/'+codes(data)+'/diagnostic');
    } else if(error.constructor.name==='APIError') results.push('error/'+serialize(error.error));
    else throw error;
  }
}
console.error=saved;
console.log(JSON.stringify(results));
'''
expected = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle, str(SDK / 'core/streaming.mjs')], input=json.dumps(cases), text=True))
def codes(text):
    return ','.join(str(ord(c)) for c in text)
arguments = ['s'+ '/'.join([str(int(done)), str(int(synthesize)), 'N' if event is None else codes(event), codes(data), codes(want)]) for (done,synthesize,event,data),want in zip(cases,expected)]
subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/ai/test/openai-sse-json-runner.bend', 'build/test-openai-sse-json'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(cases), 32):
        actual = subprocess.check_output([str(ROOT / 'build/test-openai-sse-json'), '--threads', threads, *arguments[start:start+32]], text=True, timeout=30).splitlines()
        wanted = expected[start:start+32]
        assert len(actual)==len(wanted), (start, actual, wanted)
        for offset,(got,want) in enumerate(zip(actual,wanted)):
            assert got=='pass', (threads,cases[start+offset],got,want)
    print(f'PASS SSE JSON policy: {len(cases)} SDK cases on {threads} native threads', flush=True)
