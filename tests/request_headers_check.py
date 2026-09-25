"""Compare Responses configuration assembly and HTTP projection with pi/SDK."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SDK=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
rng=random.Random(990113)
cases=[]
def case(model=None,copilot=None,format='openai',sid=None,options=None,base=None,agent='pi/test'):
    cases.append(dict(model=model,copilot=copilot,format=format,sid=sid,options=options,base=base,agent=agent))
case()
case(sid='conversation',base={'Authorization':'Bearer sdk','Content-Type':'application/json'},options={'Authorization':None,'User-Agent':None})
case(model={'X':'first','x':'second'},options={'X':'override'})
case(model={'User-Agent':'model'},copilot={'X-Initiator':'agent','Openai-Intent':'conversation-edits'},sid='one',options={'X-Initiator':'user','session_id':None})
case(sid='',format='router')
case(sid='two',format='none',options={'X-Client-Request-Id':None})
case(model={'Set-Cookie':'first'},options={'set-cookie':'second'})
case(options={'X':''},base={'x':'default'})
case(model={'X':'bad\nvalue'},options={'X':'replacement'})
case(model={'X':'bad\nvalue'},options={'x':'replacement'})
case(base={'X':'bad\nvalue'},options={'X':'replacement'})
case(model={'x-session-id':'model'},sid='generated',format='router',options={'x-session-id':None})
names=['User-Agent','user-agent','X','x','Authorization','authorization','session_id','x-session-id','X-Session-Id','x-client-request-id','X-Initiator','Copilot-Vision-Request','Set-Cookie','set-cookie','Content-Type']
values=['','first',' second ','a, b','é','\t trim \r\n','a=1; Path=/','\v']
def record(nullable=False):
    return {name:rng.choice(values+([None] if nullable else [])) for name in rng.sample(names,rng.randrange(7))}
for _ in range(700):
    case(model=record(),copilot=rng.choice([None,record()]),format=rng.choice(['openai','router','none']),sid=rng.choice([None,'','session',' different ']),options=record(True),base=record(True))
for badname,badvalue in [('bad name','x'),('','x'),('x','a\nb'),('X','🙂'),('bad:name',None)]:
    case(options={badname:badvalue},base={'X':'retained'})
script=r'''
import fs from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const {buildHeaders}=await import(process.env.PI_HEADERS_SDK+'/internal/headers.mjs');
const src=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/api/openai-responses.ts','utf8'));
const start=src.indexOf('function createClient('),end=src.indexOf('\nfunction buildParams(',start);
if(start<0||end<0)throw Error('createClient extraction failed');
const create=new Function('getCompat','getPiUserAgent','hasCopilotVisionInput','buildCopilotDynamicHeaders','OpenAI',src.slice(start,end)+';return createClient;');
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
const pairs=xs=>Array.from(xs,([k,v])=>codes(k)+';'+(v===null?'~':codes(v))).join('|');
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(c=>{
 const client=create(()=>({sessionAffinityFormat:{openai:'openai',router:'openrouter',none:'none'}[c.format]}),()=>c.agent,()=>false,()=>c.copilot,class{constructor(options){this.options=options}});
 const result=client({provider:c.copilot===null?'openai':'github-copilot',headers:c.model,baseUrl:'https://example.invalid'}, {messages:[]},'test',c.options,undefined,c.sid).options.defaultHeaders;
 let applied;
 try{const h=buildHeaders([c.base,result]).values;const record={};for(const[k,v]of h.entries())record[k]=v;
 applied='ok:'+pairs(h.entries())+'/'+h.getSetCookie().map(codes).join('|')+'/'+pairs(Object.entries(record));
 }catch{applied='error'}
 return pairs(Object.entries(result))+'#'+applied;
})));
'''
import os
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','--input-type=module','-e',script],input=json.dumps(cases),text=True,cwd=ROOT,env={**os.environ,'PI_HEADERS_SDK':str(SDK)}))
def encode(s):return ','.join(str(ord(c)) for c in s)
def record_arg(r):return '|'.join(encode(k)+';'+('~' if v is None else encode(v)) for k,v in (r or {}).items())
args=['#'.join([encode(c['agent']),record_arg(c['model']),record_arg(c['copilot']),c['format'],'n' if c['sid'] is None else 'p'+encode(c['sid']),record_arg(c['options']),record_arg(c['base'])]) for c in cases]
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/request-headers.bend','build/request-headers'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),16):
        p=subprocess.run([str(ROOT/'build/request-headers'),'--threads',threads,*args[start:start+16]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        assert p.stdout.splitlines()==expected[start:start+16],(threads,start,p.stdout,expected[start:start+16])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'request header assembly/projection comparisons PASS')
