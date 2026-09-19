"""Streaming fixed-body boundaries, exact counters, and Fetch body completion."""
import itertools
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
for n in range(7):
    data=[0,13,10,255,128,65][:n]
    for mask in range(1<<max(0,n-1)):
        chunks=[];start=0
        for i in range(1,n):
            if mask&(1<<(i-1)):chunks.append(data[start:i]);start=i
        chunks.append(data[start:])
        for length in range(n+2):cases.append((length,chunks))
rng=random.Random(335618)
for _ in range(700):
    data=[rng.randrange(256) for _ in range(rng.randrange(100))]
    cuts=sorted({0,len(data),*(rng.randrange(len(data)+1) for _ in range(8))})
    chunks=[data[a:b] for a,b in zip(cuts,cuts[1:])]
    chunks.insert(rng.randrange(len(chunks)+1),[])
    cases.append((rng.randrange(len(data)+3),chunks))
for length in [2**32-1,2**32,2**32+1,2**53+1,2**63,2**64-1]:
    cases.append((length,[[0],[],[255,13,10]]))
for length in range(5):
    for chunks in [[[256]],[[65,256]],[[65],[256]],[[255,13,10,4294967295]]]:cases.append((length,chunks))
cases += [(0,[]),(1,[]),(0,[[256]]),(1,[[65,256]])]

def codes(values):return ','.join(map(str,values))
def number(value):return str(value>>32)+','+str(value&0xffffffff)
def expected(length,chunks):
    remaining=length;emitted=[];trace=[]
    for chunk in chunks:
        trace.append('more:'+number(remaining)+':'+codes(emitted))
        size=min(remaining,len(chunk));part=chunk[:size]
        bad=next((x for x in part if x>255),None)
        if bad is not None:return '|'.join(trace+['invalid:'+str(bad)])
        remaining-=size;emitted=part
        if remaining==0:return '|'.join(trace+['done:'+codes(emitted)+':'+codes(chunk[size:])])
    trace.append('more:'+number(remaining)+':'+codes(emitted))
    trace.append('end' if remaining==0 else 'incomplete:'+number(remaining))
    return '|'.join(trace)
# Native chunk boundaries are deliberately explicit; Fetch's network chunk
# sizes are not assumed. Compare its complete body / truncated-body result.
network=[]
for n in [0,1,2,15,256,1024]:
    data=[i%256 for i in range(n)]
    network += [(n,data),(n+1,data)]
for _ in range(50):
    data=[rng.randrange(256) for _ in range(rng.randrange(80))]
    network.append((len(data),data))
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>{const [length,body]=rows[index];s.end(Buffer.concat([Buffer.from('HTTP/1.1 200 OK\r\nContent-Length: '+length+'\r\nConnection: close\r\n\r\n'),Buffer.from(body)]))})});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});results.push([...new Uint8Array(await r.arrayBuffer())])}catch{results.push(null)}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(network),cwd=ROOT,text=True,timeout=30))
for (length,data),actual in zip(network,observed,strict=True):
    assert actual==(data if length==len(data) else None),(length,data,actual)
    cases.append((length,[data]))
args=[str(length)+''.join(';'+codes(chunk) for chunk in chunks) for length,chunks in cases]
want=[expected(length,chunks) for length,chunks in cases]
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-fixed-body.bend','build/http-fixed-body'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        p=subprocess.run([str(ROOT/'build/http-fixed-body'),'--threads',threads,*args[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+32],(threads,start,p.stdout,want[start:start+32])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'fixed-body cases including',len(network),'Fetch body comparisons PASS')
