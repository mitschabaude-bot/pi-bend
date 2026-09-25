"""Synthetic credential selection against pi's actual Responses helper."""
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
def case(key=None,headers=None,provider='test-provider'):
    cases.append([provider,key,headers])
for key in [None,'','explicit-test-key',' ','\t']:
    for headers in [None,{}, {'Authorization':None},{'Authorization':''},{'Authorization':'Bearer test'},{'CF-AIG-Authorization':'gateway-test'},{'aUtHoRiZaTiOn':'test'},{'Authorization':' ','authorization':'test'},{'Authorization':'test','authorization':None}]:
        case(key,headers)
spaces=[9,10,11,12,13,32,160,5760,*range(8192,8203),8232,8233,8239,8287,12288,65279]
for code in [*range(1025),*spaces,6158,8203,8288,65535,128578]:
    for name in ['Authorization','cF-aIg-AuThOrIzAtIoN']:
        case(headers={name:chr(code)})
        case(headers={name:chr(code)+'test'+chr(code)})
case(headers={'Authorization':''.join(map(chr,spaces))})
case(provider='')
case(provider='custom/提供者')
rng=random.Random(58431)
names=['Authorization','authorization','AUTHORIZATION','CF-AIG-Authorization','cf-aig-authorization','X-Authorization','Authorization ',' AuthoriZation','Authorİzation','Ａuthorization','Cookie']
values=[None,'',' ','test','\t\r\n','\u200b','\u3000','\x00']
for _ in range(400):case(rng.choice([None,None,'','test-key']),{name:rng.choice(values) for name in rng.sample(names,rng.randrange(6))})
script=r'''
const fs=require('fs');const{stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/api/openai-responses.ts','utf8'));
const start=source.indexOf('function hasHeader('),end=source.indexOf('\nfunction detectSessionAffinityFormat(',start);
if(start<0||end<0)throw Error('helper extraction failed');
const resolve=new Function(source.slice(start,end)+';return getClientApiKey;')();
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(([provider,key,headers])=>{
 try{return 'ok:'+codes(resolve(provider,key??undefined,headers??undefined))}catch(e){return 'error:'+codes(e.message)}
})));
'''
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','-e',script],input=json.dumps(cases),cwd=ROOT,text=True))
def encode(s):return ','.join(str(ord(c)) for c in s)
def record(headers):return 'n' if headers is None else 'p'+'|'.join(encode(k)+';'+('~' if v is None else encode(v)) for k,v in headers.items())
args=['#'.join([encode(p),'n' if k is None else 'p'+encode(k),record(h)]) for p,k,h in cases]
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/responses-auth.bend','build/responses-auth'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),64):
        p=subprocess.run([str(ROOT/'build/responses-auth'),'--threads',threads,*args[start:start+64]],cwd=ROOT,capture_output=True,text=True,check=True,timeout=30)
        assert p.stdout.splitlines()==expected[start:start+64],(threads,start,p.stdout,expected[start:start+64])
        assert not p.stderr,p.stderr
    print(threads,'threads:',len(cases),'Responses credential-selection comparisons PASS')
