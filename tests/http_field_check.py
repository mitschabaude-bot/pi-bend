"""HTTP field-line syntax and actual local Fetch header projection."""
import json
import random
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
token=re.compile(rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+")
def codes(values):return ','.join(map(str,values))
def expected(row):
    if not row:return 'end'
    if any(x>255 for x in row):return 'error'
    name,colon,value=bytes(row).partition(b':')
    if not colon or not token.fullmatch(name):return 'error'
    if any(x!=9 and not 32<=x<=126 and not 128<=x<=255 for x in value):return 'error'
    return codes(name.lower())+';'+codes(value.lstrip(b' \t'))
rows=[[],list(b'X:'),list(b'X: \t '),list(b'X:a:b'),list(b'X : a'),list(b':a'),list(b' continuation'),list(b'\tcontinuation'),list(b'X'),list(b'X: a\rb'),list(b'X: a\nb')]
for byte in range(1025):
    rows += [[88,45,byte,45,89,58,32,118],[88,58,byte],[88,58,32,byte,32],[88,58,97,byte,98]]
rng=random.Random(74951)
for _ in range(500):rows.append(list(b'X-Test:')+[rng.randrange(256) for _ in range(rng.randrange(40))])
args=[codes(row) for row in rows];want=[expected(row) for row in rows]
fetch_rows=[]
for byte in range(256):
    # CR/LF are framing bytes; their invalid in-line placement is tested above.
    if byte not in [10,13]:
        fetch_rows += [[88,45,byte,45,89,58,32,118],[88,58,32,byte,32]]
fetch_rows += [list(value) for value in [b'X:',b'X: \t ',b'X:  a\tb  ',b'X: a:b',b'X : value',b'X: \xc3\xa9',b'X: \xff']]
script=r'''
import fs from 'node:fs';import net from 'node:net';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.concat([Buffer.from('HTTP/1.1 200 OK\r\n'),Buffer.from(rows[index]),Buffer.from('\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')])))});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');const results=[];
try{for(index=0;index<rows.length;index++){
 try{
  const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});await r.text();
  results.push([...r.headers].filter(([k])=>k!=='content-length'&&k!=='connection').map(([k,v])=>codes(k)+';'+codes(v)).join('|'));
 }catch{results.push('error')}
}}finally{await new Promise(resolve=>server.close(resolve))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fetch_rows),cwd=ROOT,text=True,timeout=30))
for row,result in zip(fetch_rows,observed,strict=True):
    assert result==expected(row),(row,result,expected(row))
    args.append(codes(row));want.append(result)
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/http-field.bend','build/http-field'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/http-field'),'--threads',threads,*args[start:start+64]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+64],(threads,start,p.stdout,want[start:start+64])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'field-line cases including',len(fetch_rows),'loopback Fetch comparisons PASS')
