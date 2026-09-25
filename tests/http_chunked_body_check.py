"""Incremental chunked payload/trailer decoding and live Fetch body checks."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(781925)
def codes(xs):return ','.join(map(str,xs))
def trailer_view(fields):return '|'.join(codes(k.lower().encode())+':'+codes(v.lstrip(' \t').encode('latin1')) for k,v in fields)
def frame(payloads,fields,extension=''):
    wire=[];positions=[]
    for payload in payloads:
        assert payload
        wire.extend((format(len(payload),'x')+extension+'\r\n').encode())
        positions.extend((len(wire)+i,v) for i,v in enumerate(payload))
        wire.extend(payload);wire.extend(b'\r\n')
    wire.extend(b'0\r\n')
    for k,v in fields:wire.extend((k+':'+v+'\r\n').encode('latin1'))
    wire.extend(b'\r\n')
    return wire,positions,fields
fixtures=[(list(b'0;final=value\r\nX-Trail: end\r\n\r\n'),[],[('X-Trail',' end')]),frame([],[]),frame([[65]],[]),frame([[0,255,13,10],[1,2],[65]],[('X-Trail',' one  '),('x-trail','two'),('Set-Cookie','a=1')],';test="a b"')]
for _ in range(45):
    payloads=[[rng.randrange(256) for _ in range(rng.randrange(1,25))] for _ in range(rng.randrange(1,5))]
    fields=[('X-Trail',rng.choice(['',' a ','\xff','two'])) for _ in range(rng.randrange(4))]
    fixtures.append(frame(payloads,fields,rng.choice(['',';foo',';foo=',';foo="a\\"b"'])))
args=[];want=[]
def add(chunks,result,limits=(1024,1024,16384,100)):
    args.append(';'.join([*map(str,limits),*[codes(c) for c in chunks]]));want.append(result)
def successful(fixture,chunks):
    wire,positions,fields=fixture;offset=0;trace=['more:']
    for chunk in chunks:
        end=min(offset+len(chunk),len(wire))
        data=[value for index,value in positions if offset<=index<end]
        if offset+len(chunk)>=len(wire):
            return '~'.join(trace+['done:'+codes(data)+'#'+trailer_view(fields)+'#'+codes(chunk[len(wire)-offset:])])
        trace.append('more:'+codes(data));offset+=len(chunk)
    return '~'.join(trace+['incomplete'])
for fixture in fixtures:
    wire,positions,fields=fixture;data=wire+[88,0,256]
    for split in range(len(data)+1):
        chunks=[data[:split],[],data[split:]]
        add(chunks,successful(fixture,chunks))
    chunks=[[v] for v in wire];add(chunks,successful(fixture,chunks))
for fixture in fixtures[:4]:
    for end in range(len(fixture[0])):
        chunks=[fixture[0][:end]];add(chunks,successful(fixture,chunks))
# Error outputs retain payload emitted earlier in the same call.
invalid=[(b'z\r\n','size',[]),(b'1\r\naX','delimiter',[97]),(b'1\r\na\rX','delimiter',[97]),(b'0\r\nBad Name: x\r\n\r\n','trailer',[]),(b'1;\r\n','size',[]),(b'10000000000000000\r\n','size',[])]
for wire,kind,payload in invalid:add([list(wire)],'more:~error:'+kind+':'+codes(payload))
add([[256]],'more:~error:byte:')
add([list(b'1\r\n')+[256]],'more:~error:byte:')
add([list(b'0\r\n\r\n')],'more:~error:line-limit:',(0,1024,16384,100))
add([list(b'0\r\n\r\n')],'more:~error:trailer-limit:',(1,1024,1,100))
add([list(b'0\r\nX:a\r\n\r\n')],'more:~error:line-limit:',(1,2,100,100))
add([list(b'0\r\nX:a\r\n\r\n')],'more:~error:trailer-count:',(1,3,100,0))
small=frame([], [('X','a')]);add([small[0]],successful(small,[small[0]]),(1,3,7,1))
# A huge chunk consumes only supplied bytes; EOF remains incomplete.
add([list(b'ffffffffffffffff\r\nabc')],'more:~more:97,98,99~incomplete')
# Fetch confirms body bytes and does not merge trailers into response headers.
network=[(f[0],[v for _,v in f[1]]) for f in fixtures]
network += [(list(wire),None) for wire,_,_ in invalid]
network += [(fixtures[2][0][:-1],None)]
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.concat([Buffer.from('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n'),Buffer.from(rows[index][0])])))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});const bytes=[...new Uint8Array(await r.arrayBuffer())];results.push({bytes,trail:r.headers.get('x-trail'),cookies:r.headers.getSetCookie()})}catch{results.push(null)}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(network),cwd=ROOT,text=True,timeout=30))
for (wire,payload),actual in zip(network,observed,strict=True):
    assert actual==(None if payload is None else dict(bytes=payload,trail=None,cookies=[])),(wire,actual,payload)
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/http-chunked-body.bend','build/http-chunked-body'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        p=subprocess.run([str(ROOT/'build/http-chunked-body'),'--threads',threads,*args[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=p.stdout.splitlines()
        for offset,(a,b) in enumerate(zip(actual,want[start:start+32],strict=True)):assert a==b,(threads,start+offset,args[start+offset],a,b)
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'chunked-body cases including',len(network),'Fetch responses PASS')
