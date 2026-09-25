"""Compare provider-header projection with pi's actual helper on typed values."""
import json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(7781)
cases=[None,{}, {'X-Test':None},{'X-Test':''},{'AUTHORIZATION':' a '},{'X':'1','x':'2'}, {'X':None,'Y':'ok'}]
names=['X-Test','Authorization','authorization','Retry-After','Content-Type','Empty','X-Custom']
values=[None,'','0','false',' a ','\tvalue\r\n','é','🙂']
for _ in range(700):cases.append({name:rng.choice(values) for name in rng.sample(names,rng.randrange(len(names)+1))})
script="""
const fs=require('fs');const {stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/utils/headers.ts','utf8')).replace(/^export /gm,'');
const project=new Function(source+';return providerHeadersToRecord;')();
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(value=>{
 const result=project(value??undefined);return result===undefined?'none':'some|'+Object.entries(result).map(([k,v])=>codes(k)+';'+codes(v)).join('|');
})));
"""
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','-e',script],input=json.dumps(cases),cwd=ROOT,text=True))
encode=lambda s:','.join(str(ord(c)) for c in s)
args=['n' if value is None else 'p'+''.join('|'+encode(k)+';'+('~' if v is None else encode(v)) for k,v in value.items()) for value in cases]
if '--no-build' not in sys.argv:subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/provider-headers.bend','build/provider-headers'],cwd=ROOT,check=True)
for threads in ['1','4']:
 for start in range(0,len(args),32):
  p=subprocess.run([str(ROOT/'build/provider-headers'),'--threads',threads,*args[start:start+32]],capture_output=True,text=True,cwd=ROOT,check=True,timeout=10)
  assert p.stdout.splitlines()==expected[start:start+32],(threads,start,p.stdout,expected[start:start+32])
  assert not p.stderr,p.stderr
 print(threads,'threads:',len(cases),'provider header projections PASS')
