"""Status syntax, incremental framing, and real loopback Node Fetch comparisons."""
import json
import random
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
pattern=re.compile(rb'HTTP/([0-9])\.([0-9]) ([0-9]{3})(?: ([\x09\x20-\x7e\x80-\xff]*))?')
def codes(values):return ','.join(map(str,values))
def expected(values):
    if any(v>255 for v in values):return 'error'
    match=pattern.fullmatch(bytes(values))
    if not match:return 'error'
    major,minor,status,reason=match.groups()
    return f'{int(major)}.{int(minor)}:{int(status)}:'+codes(reason or b'')
rows=[]
base=list(b'HTTP/1.1 200 OK')
for i in range(len(base)):
    for byte in range(257):rows.append(base[:i]+[byte]+base[i+1:])
rows += [base[:n] for n in range(len(base)+1)]
rows += [list(b'HTTP/1.0 204 '),list(b'HTTP/1.1 200'),list(b'HTTP/9.9 000 ')]
for byte in range(257):rows.append(list(b'HTTP/1.1 200 ')+[byte])
rng=random.Random(81591)
for _ in range(500):
    rows.append(list(f'HTTP/{rng.randrange(10)}.{rng.randrange(10)} {rng.randrange(1000):03d} '.encode())+[rng.choice([9,*range(32,127),*range(128,256)]) for _ in range(rng.randrange(30))])
args=['p;'+codes(row) for row in rows]
want=[expected(row) for row in rows]
# Verify composition with the bounded octet reader at every split point.
for line in [b'HTTP/1.1 200 OK',b'HTTP/1.0 204 ',b'HTTP/1.1 200',b'HTTP/1.1 500 \xff\tend']:
    wire=list(line+b'\r\nX: next\r\n')
    end=len(line)+2
    for split in range(len(wire)+1):
        chunks=[wire[:split],[],wire[split:]]
        args.append('s;'+';'.join(map(codes,chunks)))
        remaining=wire[end:split] if split>=end else wire[end:]
        want.append(expected(list(line))+';'+codes(remaining))
args += ['s;'+codes(list(b'HTTP/1.1 200 OK\r')), 's;'+codes(list(b'HTTP/1.1 200 \x00\r\n'))]
want += ['incomplete','error']
# Exercise the actual Fetch transport, not a hand-written Node syntax oracle.
fetch_rows=[list(b'HTTP/1.1 200 ')+[c] for c in [9,*range(32,127),*range(128,256)]]
fetch_rows += [list(f'HTTP/1.{version} {status} '.encode()) for version in [0,1] for status in [200,204,205,301,304,400,429,500,599,999]]
fetch_rows += [list(b'HTTP/1.1 200'),list(b'HTTP/1.0 200  preserved  ')]
fetch_rows += [list(b'HTTP/1.1 200 ')+list(value) for value in [b'\xc3\xa9',b'\xf0\x9f\x99\x82',b'\xe2\x82',b'\xc0\xaf',b'\xed\xa0\x80']]
script=r'''
import fs from 'node:fs';import net from 'node:net';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(socket=>{socket.on('error',()=>{});socket.once('data',()=>socket.end(Buffer.concat([Buffer.from(rows[index]),Buffer.from('\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')])))});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const output=[];
try{for(index=0;index<rows.length;index++){
 const response=await fetch('http://127.0.0.1:'+server.address().port,{redirect:'manual',signal:AbortSignal.timeout(3000)});
 await response.text();output.push([response.status,Array.from(response.statusText,c=>c.codePointAt(0))]);
}}finally{await new Promise(resolve=>server.close(resolve))}
console.log(JSON.stringify(output));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fetch_rows),cwd=ROOT,text=True,timeout=30))
for row,(status,reason) in zip(fetch_rows,observed,strict=True):
    assert status==int(bytes(row[9:12])),(row,status)
    args.append('f;'+codes(row));want.append(codes(reason))
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-status.bend','build/http-status'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/http-status'),'--threads',threads,*args[start:start+64]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+64],(threads,start,p.stdout,want[start:start+64])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'status syntax/framing cases including',len(fetch_rows),'real Fetch responses PASS')
