"""Exact Content-Length arithmetic and installed Fetch acceptance."""
import json
import random
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MAX=2**64-1
values=['',' ','\t','0','0000','1 ','1\t','\t1','1, 1','+1','-1','1.0','1e3','0x10','１２',str(MAX),str(MAX+1),str(2**53+1)]
for power in [32,53,63,64]:values += [str(2**power+delta) for delta in range(-8,9)]
for code in range(1025):values += [chr(code)+'12','12'+chr(code)]
rng=random.Random(33621)
values += ['0'*rng.randrange(8)+str(rng.randrange(2**70)) for _ in range(700)]
values += ['0'*512+'1','0'*512+str(MAX)]
def expected(value):
    # Python's arbitrary-precision integer is the numerical oracle. These
    # vectors place malformed syntax before any potentially overflowing prefix.
    if not re.fullmatch(r'[ \t]*[0-9]+ *',value):return 'invalid'
    n=int(value)
    return 'overflow' if n>MAX else str(n>>32)+','+str(n&0xffffffff)
def codes(s):return ','.join(str(ord(c)) for c in s)
args=['p;'+codes(v) for v in values];want=[expected(v) for v in values]
field_cases=[[],[('X','ignored')],[('Content-Length','0')],[('CONTENT-LENGTH',str(MAX))],[('content-length','1'),('Content-Length','1')],[('content-length','1'),('content-length','2')],[('content-length','1, 1')],[('Content-Length','0001'),('X','ignored')]]
for fields in field_cases:
    lengths=[v for k,v in fields if k.lower()=='content-length']
    result='none' if not lengths else expected(lengths[0])
    if len(lengths)>1 and result not in ['overflow','invalid']:result='duplicate'
    args.append('f'+''.join(';'+codes(k)+':'+codes(v) for k,v in fields));want.append(result)
# HEAD avoids allocating or waiting for bodies named by very large lengths.
fetch_values=['',' ','\t','0','0001','1 ','1\t','\t1',' \t1','1 \t','1, 1','+1','-1','1.0','1e3','0x10',str(MAX),str(MAX+1),str(2**53+1)]
fetch_values += [str(rng.randrange(2**65)) for _ in range(200)]
fetch_fields=[[('Content-Length',v)] for v in fetch_values]+field_cases
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.from('HTTP/1.1 200 OK\r\n'+rows[index].map(([k,v])=>k+': '+v+'\r\n').join('')+'Connection: close\r\n\r\n','latin1')))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{method:'HEAD',signal:AbortSignal.timeout(3000)});await r.text();results.push(true)}catch{results.push(false)}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fetch_fields),cwd=ROOT,text=True,timeout=30))
for fields,accepted in zip(fetch_fields,observed,strict=True):
    lengths=[v for k,v in fields if k.lower()=='content-length']
    result='none' if not lengths else expected(lengths[0])
    if len(lengths)>1 and result not in ['overflow','invalid']:result='duplicate'
    assert accepted==(result not in ['invalid','overflow','duplicate']),(fields,accepted,result)
    args.append('f'+''.join(';'+codes(k)+':'+codes(v) for k,v in fields));want.append(result)
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-content-length.bend','build/http-content-length'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/http-content-length'),'--threads',threads,*args[start:start+64]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+64],(threads,start,p.stdout,want[start:start+64])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'Content-Length cases including',len(fetch_fields),'Fetch HEAD comparisons PASS')
