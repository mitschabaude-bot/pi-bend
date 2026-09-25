"""HTTP body modes feeding native SSE, compared with real Fetch + OpenAI SDK."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SDK=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/core/streaming.mjs')
rng=random.Random(461929)
payloads=[b'',b'data: hello\n\n','event: update\ndata: é😀\n\n'.encode(),b'data: one\r\n\r\ndata: two\n\n',b'data: first\ndata: second\n\n',b'data: unfinished',b': comment\n\ndata: value\n\n',b'event: only\n\n',b'data: \xff\n\n']
for _ in range(15):payloads.append(''.join('event: update\ndata: '+rng.choice(['a','é','🙂','two'])+'\n\n' for _ in range(rng.randrange(1,5))).encode())
def wire(payload,mode):
    if mode!='chunked':return list(payload)
    # One-byte HTTP chunks split inside UTF-8 scalars and SSE line delimiters.
    return list(b''.join(b'1;x=yes\r\n'+bytes([byte])+b'\r\n' for byte in payload)+b'0\r\nX-Trail: ignored\r\n\r\n')
network=[dict(mode=mode,payload=list(payload),wire=wire(payload,mode)) for payload in payloads for mode in ['fixed','chunked','close']]
script=r'''
import fs from 'node:fs';import net from 'node:net';const {_iterSSEMessages}=await import(process.env.PI_BODY_SDK);
const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>{const c=rows[index];const framing=c.mode==='chunked'?'Transfer-Encoding: chunked\r\n':c.mode==='fixed'?'Content-Length: '+c.payload.length+'\r\n':'';s.end(Buffer.concat([Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n'+framing+'Connection: close\r\n\r\n'),Buffer.from(c.wire)]))})});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
try{for(index=0;index<rows.length;index++){
 const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});const events=[];
 for await(const e of _iterSSEMessages(r,new AbortController()))events.push((e.event===null?'none':'some:'+codes(e.event))+':'+codes(e.data));
 results.push(events.join('#'));
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
import os
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(network),cwd=ROOT,text=True,timeout=30,env={**os.environ,'PI_BODY_SDK':str(SDK)}))
def codes(xs):return ','.join(map(str,xs))
args=[];want=[]
for case,events in zip(network,observed,strict=True):
    mode=str(len(case['payload'])) if case['mode']=='fixed' else case['mode']
    data=case['wire']
    # Whole input, every split point, and all single-byte input chunks.
    partitions=[ [data[:i],[],data[i:]] for i in range(len(data)+1)]
    partitions.append([[b] for b in data])
    for chunks in partitions:
        args.append(';'.join([mode,*map(codes,chunks)]));want.append('ok|'+events+'|')
# No-body and zero-length bodies leave even invalid/unrelated bytes untouched.
for mode in ['empty','0']:
    args.append(mode+';256,65');want.append('ok||256,65')
# Close-delimited streams validate bytes and only finish at explicit clean EOF.
args += ['close;256','close;100,97,116,97,58,32,97,10,10;256','1','chunked']
want += ['error||','error|none:97|','error||','error||']
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/http-body-sse.bend','build/http-body-sse'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),16):
        p=subprocess.run([str(ROOT/'build/http-body-sse'),'--threads',threads,*args[start:start+16]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=p.stdout.splitlines()
        for offset,(a,b) in enumerate(zip(actual,want[start:start+16],strict=True)):assert a==b,(threads,start+offset,args[start+offset],a,b)
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'HTTP-to-SSE cases;',len(network),'Fetch/OpenAI SDK comparisons PASS')
