"""Buffered Fetch body preparation, compared to the actual Node Request API."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
methods = ['GET', 'get', 'HEAD', 'head', 'POST', 'put', 'delete', 'OPTIONS', 'pAtCh', 'CUSTOM', 'TRACE', '']
inputs = [('absent', []), ('text', []), ('bytes', []), ('bytes', list(range(256))), ('bytes', [0, 255, 128])]
for scalars in [[97], [0, 13, 10], [0xE9, 0x1F642], [0xD83D, 0xDE42], [0xD800], [0xDC00], [0xD800, 97, 0xDC00], [0xFEFF, 97], [0x10FFFF], [0xFFFF]]:
    inputs.append(('text', scalars))
for text in ['', '?', 'a=b+c&a=%2B', 'code=%E9&state=%EF%BB%BF', '=&&x&x=', 'emoji=🙂', 'x=\ud800', 'x=%25%2g']:
    inputs.append(('form', list(map(ord, text))))
rows = [dict(method=method, kind=kind, data=data, contentType=content_type)
        for method in methods for kind, data in inputs for content_type in [None, '', 'application/json', 'text/custom']]
for size in [65535, 65536, 65537]:
    rows.append(dict(method='POST', kind='bytes', data=[0] * size, contentType=None, repeat=size))
oracle = r'''
import fs from 'node:fs';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));const results=[];
for(const row of rows){
 try{
  const options={method:row.method,headers:row.contentType===null?{}:{'Content-Type':row.contentType}};
  if(row.kind==='text')options.body=row.data.map(n=>String.fromCodePoint(n)).join('');
  else if(row.kind==='form')options.body=new URLSearchParams(row.data.map(n=>String.fromCodePoint(n)).join(''));
  else if(row.kind==='bytes')options.body=Uint8Array.from(row.data);
  const request=new Request('http://example.test/',options);
  const absent=request.body===null;
  const bytes=[...new Uint8Array(await request.arrayBuffer())];
  results.push({method:request.method,contentType:request.headers.get('content-type'),absent,bytes});
 }catch{results.push({error:true})}
}
console.log(JSON.stringify(results));
'''
observed = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle], input=json.dumps(rows), text=True))
def numbers(values):
    return ','.join(map(str, values))
def text(value):
    return numbers(map(ord, value))
args, expected = [], []
for row, actual in zip(rows, observed, strict=True):
    fields = '-' if row['contentType'] is None else '+' + text(row['contentType'])
    args.append(';'.join([text(row['method']), 'repeat' if 'repeat' in row else row['kind'], str(row['repeat']) if 'repeat' in row else numbers(row['data']), fields]))
    if actual.get('error'):
        expected.append('error')
    else:
        fields = '-' if actual['contentType'] is None else '+' + text(actual['contentType'])
        body = 'absent' if actual['absent'] else str(len(actual['bytes'])) + ':' + numbers(actual['bytes'])
        expected.append(';'.join([text(actual['method']), fields, body]))
# Bend's explicit byte-list boundary rejects nonbytes rather than applying JS
# Uint8Array coercion. Preserve the first invalid value in the typed error.
for data, invalid in [([256], 256), ([65, 4294967295, 256], 4294967295), ([0, 255, 256, 0], 256)]:
    args.append(';'.join([text('POST'), 'bytes', numbers(data), '-']))
    expected.append('invalid-byte:' + str(invalid))
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-buffered-body.bend', 'build/http-buffered-body'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(args), 16):
        result = subprocess.run([str(ROOT / 'build/http-buffered-body'), '--threads', threads, *args[start:start + 16]], cwd=ROOT, text=True, capture_output=True, check=True, timeout=30)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start + 16], strict=True)):
            assert got == want, (threads, start + offset, args[start + offset], got, want)
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(args)} buffered body cases ({len(rows)} Node Request comparisons) PASS')
