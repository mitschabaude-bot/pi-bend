"""Buffered upload framing compared to actual Fetch over a raw loopback peer."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
methods = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'patch', 'DELETE', 'OPTIONS', 'QUERY', 'PROPFIND', 'PROPPATCH', 'CUSTOM']
lengths = [None, '', '0', '00', '3', '003', '2', '4', '+3', '-0', '3.0', '3, 3', ' 003\t', '4294967296', '9' * 80]
rows = [dict(method=method, body=body, length=length, transfer=transfer)
        for method in methods for body in ['absent', 'empty', 'data'] for length in lengths for transfer in [None, '', 'chunked']]
oracle = r'''
import fs from 'node:fs';import net from 'node:net';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));const captures=new Map();const sockets=new Set();
const server=net.createServer(s=>{
 sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});let buffer=Buffer.alloc(0),sent=false;
 s.on('data',chunk=>{if(sent)return;buffer=Buffer.concat([buffer,chunk]);const at=buffer.indexOf('\r\n\r\n');if(at<0)return;
  const lines=buffer.subarray(0,at).toString('latin1').split('\r\n');const index=Number(lines[0].split(' ')[1].slice(1));
  const headers={};for(const line of lines.slice(1)){const colon=line.indexOf(':');headers[line.slice(0,colon).toLowerCase()]=line.slice(colon+1).trim()}
  const body=buffer.subarray(at+4);const chunked=headers['transfer-encoding']==='chunked';
  if(chunked ? body.indexOf('0\r\n\r\n')<0 : body.length<Number(headers['content-length']??0))return;
  captures.set(index,{length:headers['content-length']??null,transfer:headers['transfer-encoding']??null});sent=true;
  s.end('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
 });
});await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(let i=0;i<rows.length;i++){
 const row=rows[i],headers={};if(row.length!==null)headers['content-length']=row.length;if(row.transfer!==null)headers['transfer-encoding']=row.transfer;
 try{const r=await fetch('http://127.0.0.1:'+server.address().port+'/'+i,{method:row.method,headers,...(row.body==='absent'?{}:{body:row.body==='empty'?'':'abc'}),signal:AbortSignal.timeout(1000)});await r.arrayBuffer();results.push(captures.get(i)??{error:true})}
 catch{results.push({error:true})}
}}finally{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', oracle], input=json.dumps(rows), text=True, timeout=180))
def field(value):
    return '-' if value is None else '+' + ','.join(str(ord(c)) for c in value)
args = [';'.join([r['method'], r['body'], field(r['length']), field(r['transfer'])]) for r in rows]
expected = []
for row, observation in zip(rows, observed, strict=True):
    if observation.get('error'):
        expected.append('error')
    else:
        payload = b'abc' if row['body'] == 'data' else b''
        wire = (b'3\r\nabc\r\n0\r\n\r\n' if payload else b'0\r\n\r\n') if observation['transfer'] == 'chunked' else payload
        expected.append(field(observation['length']) + ';' + field(observation['transfer']) + ';' + ','.join(map(str, wire)))
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-buffered-framing.bend', 'build/http-buffered-framing'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(args), 16):
        result = subprocess.run([str(ROOT / 'build/http-buffered-framing'), '--threads', threads, *args[start:start + 16]], cwd=ROOT, text=True, capture_output=True, check=True, timeout=30)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start + 16], strict=True)):
            assert got == want, (threads, start + offset, rows[start + offset], got, want)
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(args)} buffered framing cases against loopback Fetch PASS')
