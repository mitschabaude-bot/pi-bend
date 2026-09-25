"""Exact hexadecimal chunk lengths and actual Fetch extension acceptance."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(18452)
rows=[];want=[]
def add(row,result):rows.append(list(row));want.append(result)
def number(n):return str(n>>32)+','+str(n&0xffffffff)
for power in [0,4,32,53,63,64,68]:
    for delta in range(-8,9):
        n=max(0,2**power+delta)
        for text in [format(n,'x'),format(n,'X'),'0'*20+format(n,'x')]:add(text.encode(),number(n) if n<2**64 else 'overflow')
for _ in range(700):
    n=rng.randrange(2**68);add(format(n,'x').encode(),number(n) if n<2**64 else 'overflow')
for row in [b'',b' ',b'0x1',b'+1',b'-1',b'1 ',b'1\t',b'1\r',b'1\n',b'1g',b'\xff',[256]]:add(row,'invalid')
for byte in range(256,1025):add([49,59,120,61,34,byte,34],'invalid')
# Every response has a one-byte body; only extension syntax varies.
suffixes=[b'',b';foo',b';foo=bar',b';foo=',b';foo=""',b';foo="a\\"b"',b';foo;bar=baz',b';',b'; foo',b';foo bar',b';foo =bar',b';foo= bar',b';foo="unclosed',b';foo="x"tail',b';=x',b';;x',b';foo=token"quoted"',b';foo="x";bar',b' ;foo',b'\t;foo']
for byte in range(256):
    if byte in [10,13]:continue
    suffixes += [b';x'+bytes([byte])+b'y',b';x='+bytes([byte]),b';x="'+bytes([byte])+b'"',b';x="\\'+bytes([byte])+b'"']
for _ in range(200):
    names=[rng.choice(['foo','bar','x-1','!token']) for _ in range(rng.randrange(1,6))]
    suffixes.append(''.join(';'+name+rng.choice(['','=value','="a b"','="a\\"b"','=', '=""']) for name in names).encode())
fetch_rows=[list(b'1'+s) for s in suffixes]
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.concat([Buffer.from('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n'),Buffer.from(rows[index]),Buffer.from('\r\nx\r\n0\r\n\r\n')])))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});results.push(await r.text()==='x')}catch{results.push(false)}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
accepted=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fetch_rows),cwd=ROOT,text=True,timeout=30))
for row,ok in zip(fetch_rows,accepted,strict=True):add(row,'0,1' if ok else 'invalid')
args=[','.join(map(str,row)) for row in rows]
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/http-chunk-size.bend','build/http-chunk-size'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/http-chunk-size'),'--threads',threads,*args[start:start+64]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=p.stdout.splitlines()
        for offset,(a,b) in enumerate(zip(actual,want[start:start+64],strict=True)):
            assert a==b,(threads,start+offset,rows[start+offset],a,b)
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(rows),'chunk-size cases including',len(fetch_rows),'Fetch extension comparisons PASS')
