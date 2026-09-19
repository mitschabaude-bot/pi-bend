"""Ordered framing-header analysis compared with the installed Fetch runtime."""
import json
import random
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[[],[('X','ordinary')]]
values=['',' ','\t','chunked','Chunked','chunked ','chunked\t','gzip','gzip, chunked','chunked, gzip','chunked, chunked','chunked;foo=bar','gzip;foo="a,b", chunked',',chunked','chunked,','gzip,\tchunked','gzip,,chunked','gzip, chunked\t']
for value in values:
    cases.append([('Transfer-Encoding',value)])
    for previous in ['', 'chunked','gzip']:
        cases.append([('Transfer-Encoding',previous),('transfer-encoding',value)])
    for length in ['0','0005','18446744073709551615','18446744073709551616','1, 1','1\t']:
        cases += [[('Transfer-Encoding',value),('Content-Length',length)],[('Content-Length',length),('Transfer-Encoding',value)]]
rng=random.Random(24881)
for _ in range(500):
    fields=[]
    for _ in range(rng.randrange(6)):
        key=rng.choice(['Transfer-Encoding','transfer-encoding','Content-Length','content-length','X-Test'])
        value=rng.choice(values) if key.lower()=='transfer-encoding' else rng.choice(['','0','5','5 ','1\t','12','0001']) if key.lower()=='content-length' else 'ignored'
        fields.append((key,value))
    cases.append(fields)

def expected(fields):
    length=None;encoding='absent'
    for key,value in fields:
        key=key.lower()
        if key=='transfer-encoding':
            if length is not None:return 'error'
            text=value.lstrip(' \t')
            if text:encoding='chunked' if text.split(',')[-1].lstrip(' \t').rstrip(' ').lower()=='chunked' else 'other'
        if key=='content-length':
            if encoding!='absent' or length is not None:return 'error'
            if not re.fullmatch(r'[ \t]*[0-9]+ *',value):return 'error'
            length=int(value)
            if length>=2**64:return 'error'
    return encoding+';'+('none' if length is None else str(length>>32)+','+str(length&0xffffffff))
want=[expected(fields) for fields in cases]
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const payload='3\r\nabc\r\n0\r\n\r\n';
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.from('HTTP/1.1 200 OK\r\n'+rows[index].map(([k,v])=>k+': '+v+'\r\n').join('')+'Connection: close\r\n\r\n'+payload,'latin1')))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 const head=rows[index].some(([k])=>k.toLowerCase()==='content-length');
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{method:head?'HEAD':'GET',signal:AbortSignal.timeout(3000)});const text=await r.text();results.push(head?'accepted':text==='abc'?'chunked':text===payload?'close':'unexpected:'+text)}catch{results.push('error')}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(cases),cwd=ROOT,text=True,timeout=30))
for fields,result,actual in zip(cases,want,observed,strict=True):
    target='error' if result=='error' else 'accepted' if any(k.lower()=='content-length' for k,v in fields) else 'chunked' if result.startswith('chunked;') else 'close'
    assert actual==target,(fields,result,actual,target)
want=[result if result=='error' else result+';'+('chunked' if result.startswith('chunked;') else 'close' if result.endswith(';none') else 'fixed:'+result.split(';')[1]) for result in want]
def codes(s):return ','.join(str(ord(c)) for c in s)
args=[';'.join(codes(k)+':'+codes(v) for k,v in fields) for fields in cases]
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-framing-fields.bend','build/http-framing-fields'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        p=subprocess.run([str(ROOT/'build/http-framing-fields'),'--threads',threads,*args[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+32],(threads,start,p.stdout,want[start:start+32])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'ordered framing-header / Fetch comparisons PASS')
