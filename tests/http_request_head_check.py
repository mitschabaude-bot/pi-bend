"""Request method policy and outgoing HTTP/1.1 head bytes."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
rows = []
for base in ['delete', 'get', 'head', 'options', 'post', 'put', 'connect', 'trace', 'track', 'patch']:
    for bits in range(1 << len(base)):
        method = ''.join(c.upper() if bits & (1 << i) else c for i, c in enumerate(base))
        rows.append(dict(method=method, target='/v1/responses?stream=true', headers=[]))
for code in range(258):
    rows.append(dict(method='X' + chr(code), target='/', headers=[]))
    rows.append(dict(method='POST', target='/', headers=[['x' + chr(code), 'value']]))
    rows.append(dict(method='POST', target='/', headers=[['x-test', 'a' + chr(code) + 'b']]))
for method in ['', 'M SEARCH', 'pAtCh', 'PROPFIND', 'GET\r\nX: yes', '\U0001f600']:
    rows.append(dict(method=method, target='/', headers=[]))
for target in ['', '*', 'relative', '/space here', '/#fragment', '/\r\nGET /', '/café', '/a?x=%00', '//a///b?x=y', '/x%2Fy?z=%23']:
    rows.append(dict(method='POST', target=target, headers=[]))
for headers in [[['x-a', ''], ['x-a', '2']], [['Cookie', 'a=1'], ['Cookie', 'b=2']], [['Host', 'example.test'], ['Content-Length', '3']], [['x-high', '\xff']], [['bad name', 'bad\r\nvalue']]]:
    rows.append(dict(method='post', target='/x', headers=headers))

oracle = r'''
import fs from 'node:fs';import {validateHeaderName,validateHeaderValue} from 'node:http';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(row=>{
 try {
  const method=new Request('http://example.test/',{method:row.method}).method;
  for(const [name,value] of row.headers){validateHeaderName(name);validateHeaderValue(name,value)}
  return {method};
 }catch{return {error:true}}
})));
'''
observed = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle], input=json.dumps(rows), text=True))
args, expected = [], []
def codes(text):
    return ','.join(str(ord(c)) for c in text)
for row, actual in zip(rows, observed, strict=True):
    args.append(';'.join([codes(row['method']), codes(row['target']), *[codes(item) for pair in row['headers'] for item in pair]]))
    target = row['target']
    # This layer consumes an encoded origin-form target, not an arbitrary URL.
    valid_target = target.startswith('/') and all(33 <= ord(c) <= 126 and c != '#' for c in target)
    if actual.get('error') or not valid_target:
        expected.append('error')
    else:
        method = actual['method']
        wire = method + ' ' + target + ' HTTP/1.1\r\n' + ''.join(name + ': ' + value + '\r\n' for name, value in row['headers']) + '\r\n'
        expected.append(codes(method) + ';' + codes(wire))
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-request-head.bend', 'build/http-request-head'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(args), 16):
        result = subprocess.run([str(ROOT / 'build/http-request-head'), '--threads', threads, *args[start:start + 16]], cwd=ROOT, text=True, capture_output=True, check=True, timeout=30)
        for i, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start + 16], strict=True)):
            assert got == want, (threads, start + i, rows[start + i], got, want)
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(args)} request-head cases with Node method/header oracle PASS')
