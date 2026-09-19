"""Response-head assembly, bounds and duplicate-field projections."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def codes(values):return ','.join(map(str,values))
def pairs(items):return '|'.join(codes(k.encode('latin1'))+':'+codes(v.encode('latin1')) for k,v in items)
fixtures=[[],['X: a  ','x: b\t','Set-Cookie: a=1','set-cookie: b=2','Cookie: a=1','cookie: b=2'],['Empty:','X: \xff'],['Z: z','A: a','z: last']]
rng=random.Random(920154)
for _ in range(100):
    fixtures.append([rng.choice(['X','x','A','Z','Cookie','Set-Cookie'])+':'+rng.choice(['',' a ','\tvalue\t','\xff','one','two']) for _ in range(rng.randrange(10))])

def wire(fields):return ('HTTP/1.1 200 OK\r\n'+'\r\n'.join(fields)+ ('\r\n' if fields else '')+'\r\n').encode('latin1')
def raw_fields(fields):return [(k.lower(),v.lstrip(' \t')) for k,_,v in (f.partition(':') for f in fields)]
def projection(fields):
    groups={}
    for k,v in raw_fields(fields):groups.setdefault(k,[]).append(v)
    entries=[]
    for k,vs in sorted(groups.items()):
        entries.extend([(k,v) for v in vs] if k=='set-cookie' else [(k,('; ' if k=='cookie' else ', ').join(vs))])
    return pairs(entries)+'#'+'|'.join(codes(v.encode('latin1')) for v in groups.get('set-cookie',[]))

def result(fields,rest):return '1.1:200:79,75#'+pairs(raw_fields(fields))+'#'+projection(fields)+'#'+codes(rest)
args=[];want=[]
def add(chunks,expected,line=1024,head=16384,count=100):
    args.append(';'.join([str(line),str(head),str(count),*[codes(chunk) for chunk in chunks]]));want.append(expected)
for fields in fixtures:
    head=wire(fields);seq=list(head)+[0,255,13,10,256]
    for split in range(len(seq)+1):
        chunks=[seq[:split],[],seq[split:]]
        rest=seq[len(head):split] if split>=len(head) else seq[len(head):]
        add(chunks,result(fields,rest))
    # One byte per chunk, exercising every state boundary in the same run.
    add([[x] for x in head],result(fields,[]))
    line=max(map(len,head.split(b'\r\n')))
    add([list(head)],result(fields,[]),line,len(head),len(fields))
    add([list(head)],'line-limit',line-1,len(head)+10,len(fields)+1)
    add([list(head)],'head-limit',line+1,len(head)-1,len(fields)+1)
    if fields:add([list(head)],'field-limit',line+1,len(head)+10,len(fields)-1)
head=wire(['X: a'])
for n in range(len(head)):add([list(head[:n])],'incomplete')
add([list(b'not HTTP\r\n')],'status')
add([list(b'HTTP/1.1 200 OK\r\nBad Name: value\r\n\r\n')],'field')
add([list(b'HTTP/1.1 200 OK\r\nX: a\r\n continued\r\n\r\n')],'field')
add([[256]],'framing')
add([list(head)],'head-limit',1024,0,100)
# Actual Fetch projects duplicates from received values, including trailing OWS.
script=r'''
import fs from 'node:fs';import net from 'node:net';const fixtures=JSON.parse(fs.readFileSync(0,'utf8'));let index=0;
const server=net.createServer(s=>{s.on('error',()=>{});s.once('data',()=>s.end(Buffer.from('HTTP/1.1 200 OK\r\n'+fixtures[index].join('\r\n')+(fixtures[index].length?'\r\n':'')+'Content-Length: 0\r\nConnection: close\r\n\r\n','latin1')))});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const output=[];const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
try{for(index=0;index<fixtures.length;index++){
 const r=await fetch('http://127.0.0.1:'+server.address().port,{signal:AbortSignal.timeout(3000)});await r.text();
 output.push([...r.headers].filter(([k])=>k!=='connection'&&k!=='content-length').map(([k,v])=>codes(k)+':'+codes(v)).join('|')+'#'+r.headers.getSetCookie().map(codes).join('|'));
}}finally{await new Promise(r=>server.close(r))}
console.log(JSON.stringify(output));
'''
observed=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],input=json.dumps(fixtures),cwd=ROOT,text=True,timeout=30))
for fields,actual in zip(fixtures,observed,strict=True):assert actual==projection(fields),(fields,actual,projection(fields))
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-head.bend','build/http-head'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        p=subprocess.run([str(ROOT/'build/http-head'),'--threads',threads,*args[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==want[start:start+32],(threads,start,p.stdout,want[start:start+32])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(args),'response-head cases;',len(fixtures),'Fetch duplicate projections PASS')
