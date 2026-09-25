"""Immutable header operation traces against Node Headers and pi's projection."""
import json
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(94112)
cases = [
    [('a','Cookie','a=1'),('a','cookie','b=2'),('g','COOKIE'),('s','cookie','c=3'),('a','Cookie',''),('g','cookie')],
    [('a','X',''),('g','x'),('h','X'),('a','x','two'),('s','X','three'),('d','x'),('g','X'),('h','x')],
    [('a','Set-Cookie','a=1'),('a','set-cookie','b=2'),('g','SET-COOKIE'),('s','Set-Cookie','c=3'),('a','SET-COOKIE',''),('d','set-cookie')],
    [('a','z','last'),('a','B','first'),('a','a','zero'),('a','b','second'),('s','Z','replacement'),('d','b'),('a','B','new')],
    [('a','X','valid'),('a','X','bad\nvalue'),('s','bad name','x'),('d',''),('g','bad:name'),('h','🙂'),('g','X')],
]
names = ['X','x','A','Z','Content-Type','set-cookie','Set-Cookie','Retry-After','x-0','X-0','bad name','','bad:name','é']
values = ['', 'a', 'b, c', 'a=1; Path=/', 'b=2; Expires=Wed, 01 Jan 2031 00:00:00 GMT', '\t x \r\n', 'é', '\x00', 'x\ny', '🙂', '\v', '\xff']
for _ in range(500):
    case = []
    for _ in range(rng.randrange(8,25)):
        op = rng.choice('aasdgh')
        item = (op, rng.choice(names))
        if op in 'as': item += (rng.choice(values),)
        case.append(item)
    cases.append(case)
script = r'''
const fs=require('fs');const {stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/utils/headers.ts','utf8')).replace(/^export /gm,'');
const project=new Function(source+';return headersToRecord;')();
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
const pairs=xs=>Array.from(xs,([k,v])=>codes(k)+';'+codes(v)).join('|');
const snapshot=h=>pairs(h.entries())+'/'+h.getSetCookie().map(codes).join('|')+'/'+pairs(Object.entries(project(h)));
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(ops=>{
 let h=new Headers();return ops.map(([op,name,value])=>{
  const before=snapshot(h);let result;
  try {
   if(op==='a'){h.append(name,value);result='ok'}
   if(op==='s'){h.set(name,value);result='ok'}
   if(op==='d'){h.delete(name);result='ok'}
   if(op==='g'){const v=h.get(name);result=v===null?'none':'some:'+codes(v)}
   if(op==='h')result=String(h.has(name));
  }catch{result='error'}
  return before+'>'+result+'>'+snapshot(h);
 }).join('~');
})));
'''
expected = json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','-e',script],input=json.dumps(cases),text=True,cwd=ROOT))
def encode(text): return ','.join(str(ord(c)) for c in text)
# Native dictionaries intentionally keep JS prototype-looking names ordinary.
# This is a separate native-value contract, not an adjusted upstream oracle.
ordinary = [('a','__proto__','ordinary'),('a','constructor','also ordinary'),('a','toString','text')]
state = {}
traces = []
def native_snapshot():
    fields = '|'.join(encode(k)+';'+encode(v) for k,v in sorted(state.items()))
    return fields+'//'+fields
for _, name, value in ordinary:
    before = native_snapshot()
    state[name.lower()] = value
    traces.append(before+'>ok>'+native_snapshot())
cases.append(ordinary)
expected.append('~'.join(traces))
args = ['|'.join(';'.join([op[0], *map(encode,op[1:])]) for op in case) for case in cases]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/headers.bend','build/headers'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),16):
        result=subprocess.run([str(ROOT/'build/headers'),'--threads',threads,*args[start:start+16]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=result.stdout.splitlines()
        assert actual==expected[start:start+16],(threads,start,actual,expected[start:start+16])
        assert not result.stderr,result.stderr
    print(threads,'threads:',len(cases),'sequences,',sum(map(len,cases)),'operations PASS')
