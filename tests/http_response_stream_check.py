"""Whole response decoder: ordered events, body framing and EOF boundaries."""
import json
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def fixture(mode='fixed',status=200,method='GET',info=(),payload=b'abc\x00\xff'):
    wire=[];heads=[];positions=[]
    for code in info:
        wire.extend(f'HTTP/1.1 {code} Info\r\n\r\n'.encode());heads.append((len(wire),'info:'+str(code)))
    nobody=method=='HEAD' or status in [204,304]
    expose=not nobody and status!=205
    field='Content-Length: '+str(len(payload))+'\r\n' if mode=='fixed' else 'Transfer-Encoding: chunked\r\n' if mode=='chunked' else ''
    wire.extend((f'HTTP/1.1 {status} Status\r\n'+field+'Connection: close\r\n\r\n').encode())
    final_head=len(wire);heads.append((final_head,'head:'+str(status)+(':'+('body' if expose else 'null'))))
    if not nobody:
        if mode=='chunked':
            for byte in payload:
                wire.extend(b'1;x=value\r\n');positions.append((len(wire),byte));wire.append(byte);wire.extend(b'\r\n')
            wire.extend(b'0\r\nX-Trail: separate\r\n\r\n')
        else:
            positions.extend((len(wire)+i,b) for i,b in enumerate(payload));wire.extend(payload)
    return dict(wire=wire,heads=heads,positions=positions,final_head=final_head,close=mode=='close' and not nobody,expose=expose,method=method,status=status,payload=list(payload) if expose else [],done='done:'+','.join(map(str,b'x-trail'))+':'+','.join(map(str,b'separate')) if mode=='chunked' and not nobody else 'done')
fixtures=[]
for mode in ['fixed','chunked','close']:
    for status in [200,204,205,304]:
        for info in [(),(103,),(102,103,199)]:fixtures.append(fixture(mode,status,info=info))
    fixtures.append(fixture(mode,method='HEAD',info=(103,)))
    fixtures.append(fixture(mode,payload=b''))

def codes(xs):return ','.join(map(str,xs))
def summary(status,events,rest=()):return status+'|'+'~'.join(events)+'|'+codes(rest)
def expected(f,chunks):
    trace=['more||'];offset=0
    for chunk in chunks:
        end=min(offset+len(chunk),len(f['wire']))
        events=[value for position,value in f['heads'] if offset<position<=end]
        payload=[v for position,v in f['positions'] if offset<=position<end]
        if payload and f['expose']:events.append('data:'+codes(payload))
        if not f['close'] and offset+len(chunk)>=len(f['wire']):
            return '#'.join(trace+[summary('complete',events+[f['done']],chunk[len(f['wire'])-offset:])])
        trace.append(summary('more',events));offset+=len(chunk)
    trace.append(summary('complete',['done']) if f['close'] and offset>=f['final_head'] else summary('error',[]))
    return '#'.join(trace)
args=[];want=[]
def add(method,chunks,result,budget=8):
    args.append(';'.join([method,str(budget),*[codes(c) for c in chunks]]));want.append(result)
for f in fixtures:
    data=f['wire']+([] if f['close'] else [88,256])
    for split in range(len(data)+1):
        chunks=[data[:split],[],data[split:]];add(f['method'],chunks,expected(f,chunks))
    chunks=[[b] for b in f['wire']];add(f['method'],chunks,expected(f,chunks))
for f in [fixtures[2],fixtures[14],fixtures[28]]:
    for end in range(len(f['wire'])):
        chunks=[f['wire'][:end]];add(f['method'],chunks,expected(f,chunks))
info=fixture(info=(103,102))
add('GET',[info['wire']],'more||#error|info:103|',budget=1)
add('GET',[info['wire']],'more||#error||',budget=0)
add('GET',[list(b'HTTP/1.1 100 Continue\r\n\r\n')],'more||#error||')
add('GET',[list(b'HTTP/1.1 200 OK\r\nBad Name:x\r\n\r\n')],'more||#error||')
add('GET',[list(b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\naX')],'more||#error|head:200:body~data:97|')
# Compare complete public responses using the actual Fetch transport. This does
# not assume its network chunk boundaries match the native event batches.
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.from(rows[index].wire)))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 const r=await fetch('http://127.0.0.1:'+server.address().port,{method:rows[index].method,signal:AbortSignal.timeout(3000)});
 results.push({status:r.status,expose:r.body!==null,payload:[...new Uint8Array(await r.arrayBuffer())]});
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fixtures),cwd=ROOT,text=True,timeout=30))
for f,actual in zip(fixtures,observed,strict=True):assert actual=={k:f[k] for k in ['status','expose','payload']},(f,actual)
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-response-stream.bend','build/http-response-stream'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),16):
        p=subprocess.run([str(ROOT/'build/http-response-stream'),'--threads',threads,*args[start:start+16]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=p.stdout.splitlines()
        for offset,(a,b) in enumerate(zip(actual,want[start:start+16],strict=True)):assert a==b,(threads,start+offset,args[start+offset],a,b)
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'whole-response cases;',len(fixtures),'Fetch comparisons PASS')
