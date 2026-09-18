"""Compare own property inspection with actual ECMAScript reflection."""
import json
from pathlib import Path
import random
import subprocess
from schema_test_values import string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
rng=random.Random(85119)
names=['a','hidden','0','2','10','01','4294967294','4294967295','__proto__','😀']
cases=[]
for array in [False,True]:
 for size in [0,1,5,10]:
  for repeat in range(3):
   chosen=rng.sample(names,size)
   props=[]
   for i,name in enumerate(chosen):
    d={'kind':'data','value':i+1,'writable':bool(rng.randrange(2)),'enumerable':bool(rng.randrange(2)),'configurable':bool(rng.randrange(2))} if i%2==0 else {'kind':'accessor','get':1 if i%3 else None,'set':2 if i%3 else None,'enumerable':bool(rng.randrange(2)),'configurable':bool(rng.randrange(2))}
    props.append([['s',name],d])
   for symbol in [8,3]:props.append([['y',symbol],{'kind':'accessor','get':1,'set':None,'enumerable':False,'configurable':True}])
   cases.append(dict(array=array,props=props,writable=bool(repeat%2),queries=[['s',n]for n in names+['length','missing','inherited']]+[['y',8],['y',3],['y',99]]))
oracle='''let text='';for await(const x of process.stdin)text+=x;
let invoked=0;const getters={1:()=>{invoked++;return 99}},setters={2:()=>{invoked++}};
function key(k){return k[0]==='s'?k[1]:Symbol.for(String(k[1]));}
function wireKey(k){return typeof k==='symbol'?['y',Number(Symbol.keyFor(k))]:['s',k];}
function wire(d){if(!d)return null;const common={enumerable:d.enumerable,configurable:d.configurable};return 'value'in d?{...common,kind:'data',value:d.value,writable:d.writable}:{...common,kind:'accessor',get:d.get?1:null,set:d.set?2:null};}
const output=JSON.parse(text).map(c=>{const o=c.array?[]:{};Object.setPrototypeOf(o,{inherited:42});for(const [k,d]of c.props){const desc={enumerable:d.enumerable,configurable:d.configurable};if(d.kind==='data'){desc.value=d.value;desc.writable=d.writable;}else{desc.get=getters[d.get];desc.set=setters[d.set];}Object.defineProperty(o,key(k),desc);}if(c.array)Object.defineProperty(o,'length',{writable:c.writable});return {length:c.array?o.length:0,keys:Reflect.ownKeys(o).map(wireKey),descriptors:c.queries.map(k=>wire(Reflect.getOwnPropertyDescriptor(o,key(k))))};});
if(invoked)throw new Error('inspection invoked accessor');console.log(JSON.stringify(output));'''
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',oracle],input=json.dumps(cases),text=True))
def flag(v):return 'True{}'if v else 'False{}'
def key(k):return 'O.StringKey{'+string(map(ord,k[1]))+'}' if k[0]=='s' else f'O.SymbolKey{{{k[1]}}}'
def optional(v):return 'None{}' if v is None else f'Some{{{v}}}'
def descriptor(d):
 if d['kind']=='data':return 'V.DataProperty{V.Number{F.fromU32('+str(d['value'])+')}, '+', '.join(flag(d[k])for k in ['writable','enumerable','configurable'])+'}'
 return 'V.AccessorProperty{'+', '.join([optional(d['get']),optional(d['set']),flag(d['enumerable']),flag(d['configurable'])])+'}'
def listing(items):return ' <> '.join(items+['Nil{}'])
lines=['import Base','import ../packages/runtime/test/object.bend as T','import ../packages/runtime/src/object.bend as O','import ../packages/runtime/src/value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,expect)in enumerate(zip(cases,expected,strict=True)):
 props='R.new(T.D())';symbols=[]
 for k,d in case['props']:
  if k[0]=='s':props=f'R.set(T.D(), {props}, {string(map(ord,k[1]))}, {descriptor(d)})'
  else:symbols.append(f'V.SymbolProperty{{{k[1]}, {descriptor(d)}}}')
 queries=[f'T.Query{{{key(k)}, '+('None{}'if d is None else 'Some{'+descriptor(d)+'}')+'}'for k,d in zip(case['queries'],expect['descriptors'],strict=True)]
 lines += [f'def case{i}() -> IO(Unit):',f'  T.run({flag(case["array"])}, {expect["length"]}, {flag(case["writable"])}, {props}, {listing(symbols)}, {listing([key(k)for k in expect["keys"]])}, {listing(queries)})']
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()'for i in range(len(cases))]+['    T.live()', '    T.errors()',f'    IO.print("PASS {len(cases)} own-key orders, {sum(len(c["queries"])for c in cases)} descriptors and live inspection")']
source=BUILD/'object-inspection-vectors.bend';source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-object-inspection'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=60)
