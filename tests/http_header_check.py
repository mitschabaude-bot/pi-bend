"""Compare typed header normalization with Node's native Fetch Headers."""
import json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
for code in [*range(1025),0xd800,0xdfff,0x10000,0x1f642,0x10ffff]:
 ch=chr(code)
 cases += [[ch,'value'],['X'+ch+'-Y','value'],['X-Test',ch],['X-Test','a'+ch+'b'],['X-Test',' \t'+ch+'\r\n']]
for name in ['',"!#$%&'*+-.^_`|~",'ReTrY-AfTeR','X-Should-Retry','__proto__','constructor','toString']:
 for value in ['', ' \ttrue\r\n','\r\n1000\t','\vtrue\f','a,b', 'é','🙂']:
  cases.append([name,value])
rng=random.Random(911022)
for _ in range(600):
 name=rng.choice(['X-Test','Retry-After','Authorization','invalid name'])
 value=''.join(chr(rng.randrange(256)) for _ in range(rng.randrange(40)))
 cases.append([name,value])
script="""
const fs=require('fs');const cases=JSON.parse(fs.readFileSync(0,'utf8'));
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
console.log(JSON.stringify(cases.map(([name,value])=>{try{
 const h=new Headers([[name,value]]);const [[key,text]]=Array.from(h.entries());
 return 'ok:'+codes(key)+';'+codes(text);
}catch{return 'error';}})));
"""
expected=json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(cases),cwd=ROOT,text=True))
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/http-header.bend','build/http-header'],cwd=ROOT,check=True)
encode=lambda s:','.join(str(ord(ch)) for ch in s)
for threads in ['1','4']:
 for start in range(0,len(cases),32):
  args=[encode(name)+';'+encode(value) for name,value in cases[start:start+32]]
  result=subprocess.run([str(ROOT/'build/http-header'),'--threads',threads,*args],cwd=ROOT,text=True,capture_output=True,check=True,timeout=10)
  assert result.stdout.splitlines()==expected[start:start+32],(threads,start,cases[start:start+32],result.stdout,expected[start:start+32])
  assert not result.stderr,result.stderr
 print(threads,'threads:',len(cases),'HTTP header normalization comparisons PASS')
