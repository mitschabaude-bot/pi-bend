"""Method/status policy and ordinary Fetch response exposure."""
import json
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
def add(status=200,method='GET',version=(1,1),fields=None):
    cases.append(dict(status=status,method=method,major=version[0],minor=version[1],fields=[('Content-Length','0')] if fields is None else fields))
for major in range(10):
    for minor in range(10):add(version=(major,minor))
for status in [0,1,99,100,101,102,103,150,199,200,201,204,205,206,299,301,304,400,500,599,600,999]:
    for method in ['GET','HEAD','POST']:
        for fields in [[],[('Content-Length','0')],[('Content-Length','3')],[('Transfer-Encoding','chunked')],[('Transfer-Encoding','gzip')],[('Content-Length','invalid')],[('Content-Length','0'),('Content-Length','0')],[('Transfer-Encoding','chunked'),('Content-Length','0')]]:
            add(status,method,fields=fields)

def expected(c):
    if (c['major'],c['minor']) not in [(0,9),(1,0),(1,1),(2,0)]:return 'error'
    fields=c['fields']
    if any(v=='invalid' for k,v in fields) or sum(k=='Content-Length' for k,v in fields)>1 or any(k=='Transfer-Encoding' for k,v in fields) and any(k=='Content-Length' for k,v in fields):return 'error'
    status=c['status']
    if status<102 or status>999:return 'error'
    if status<200:return 'next'
    if c['method']=='HEAD' or status in [204,304]:return 'final:empty:null'
    expose='null' if status==205 else 'body'
    if fields and fields[0][0]=='Content-Length':mode='fixed:0,'+fields[0][1]
    elif fields and fields[0][1]=='chunked':mode='chunked'
    else:mode='close'
    return 'final:'+mode+':'+expose
want=[expected(c) for c in cases]
for c,result in zip(cases,want):
    # Supply complete payloads for final responses; informational heads precede
    # a normal final response, without prematurely closing their connection.
    c['payload']='3\r\nabc\r\n0\r\n\r\n' if ':chunked:' in result else 'abc' if ':close:' in result or ':fixed:0,3:' in result else ''
script=r'''
import fs from 'node:fs';import net from 'node:net';const rows=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>{const c=rows[index];const interim=c.status>=100&&c.status<200;let wire='HTTP/'+c.major+'.'+c.minor+' '+String(c.status).padStart(3,'0')+' Status\r\n'+c.fields.map(([k,v])=>k+': '+v+'\r\n').join('')+(interim?'':'Connection: close\r\n')+'\r\n'+c.payload;if(interim)wire+='HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n';s.end(wire)})});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const results=[];
try{for(index=0;index<rows.length;index++){
 try{const r=await fetch('http://127.0.0.1:'+server.address().port,{method:rows[index].method,signal:AbortSignal.timeout(3000)});results.push({status:r.status,nullBody:r.body===null,text:await r.text()})}catch{results.push(null)}
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(results));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(cases),cwd=ROOT,text=True,timeout=30))
for c,result,actual in zip(cases,want,observed,strict=True):
    if result=='error':target=None
    elif result=='next':target=dict(status=200,nullBody=c['method']=='HEAD',text='')
    else:
        null=result.endswith(':null')
        target=dict(status=c['status'],nullBody=null,text='' if null or ':fixed:0,0:' in result else 'abc')
    assert actual==target,(c,result,actual,target)
def codes(s):return ','.join(str(ord(x)) for x in s)
args=[';'.join([c['method'],str(c['major']),str(c['minor']),str(c['status']),*[codes(k)+':'+codes(v) for k,v in c['fields']]]) for c in cases]
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/http-response-policy.bend','build/http-response-policy'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        p=subprocess.run([str(ROOT/'build/http-response-policy'),'--threads',threads,*args[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+32],(threads,start,p.stdout,want[start:start+32])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'response policy / Fetch comparisons PASS')
