"""Differential deletion sequences, including descriptors and key order."""
import json
from pathlib import Path
import subprocess
from schema_test_values import string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
def flag(v):return 'True{}'if v else 'False{}'
def optional(v):return 'None{}'if v is None else f'Some{{{v}}}'
def key(k):return 'O.StringKey{'+string(map(ord,k[1]))+'}'if k[0]=='s'else f'O.SymbolKey{{{k[1]}}}'
def descriptor(d):
 if d['kind']=='data':return 'V.DataProperty{V.Number{F.fromU32('+str(d['value'])+')}, '+', '.join(flag(d[k])for k in ['writable','enumerable','configurable'])+'}'
 return 'V.AccessorProperty{'+', '.join([optional(d['get']),optional(d['set']),flag(d['enumerable']),flag(d['configurable'])])+'}'
def listing(items):return ' <> '.join(items+['Nil{}'])
cases=[]
for array in [False,True]:
 for extensible in [False,True]:
  for writable in [False,True]:
   for configurable in [False,True]:
    props=[]
    for i,k in enumerate([['s','2'],['s','0'],['s','hidden'],['s','01'],['s','__proto__'],['s','😀'],['y',3],['y',4]]):
     desc=dict(kind='data',value=i+1,writable=writable,enumerable=bool(i%2),configurable=configurable if i%2 else not configurable) if i%3 else dict(kind='accessor',get=1,set=2,enumerable=False,configurable=configurable)
     props.append([k,desc])
    keys=[['s','inherited'],['s','missing'],['s','length'],['y',99]]+[k for k,_ in reversed(props)]
    cases.append(dict(array=array,extensible=extensible,writable=writable,props=props,deletes=[k for k in keys for _ in range(2)]))
oracle='''let text='';for await(const x of process.stdin)text+=x;
let invoked=0;const getters={1:()=>{invoked++;return 99}},setters={2:()=>{invoked++}};
function key(k){return k[0]==='s'?k[1]:Symbol.for(String(k[1]));}
function wireKey(k){return typeof k==='symbol'?['y',Number(Symbol.keyFor(k))]:['s',k];}
function wire(d){if(!d)return null;const common={enumerable:d.enumerable,configurable:d.configurable};return 'value'in d?{...common,kind:'data',value:d.value,writable:d.writable}:{...common,kind:'accessor',get:d.get?1:null,set:d.set?2:null};}
const out=JSON.parse(text).map(c=>{const o=c.array?[]:{};Object.setPrototypeOf(o,{inherited:42});for(const[k,d]of c.props){let desc={enumerable:d.enumerable,configurable:d.configurable};if(d.kind==='data'){desc.value=d.value;desc.writable=d.writable}else{desc.get=getters[d.get];desc.set=setters[d.set]}Object.defineProperty(o,key(k),desc)}if(c.array)Object.defineProperty(o,'length',{writable:c.writable});if(!c.extensible)Object.preventExtensions(o);const length=c.array?o.length:0;return {length,steps:c.deletes.map(k=>({success:Reflect.deleteProperty(o,key(k)),keys:Reflect.ownKeys(o).map(wireKey),descriptor:wire(Reflect.getOwnPropertyDescriptor(o,key(k)))}))};});
if(invoked)throw new Error('delete invoked an accessor');console.log(JSON.stringify(out));'''
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',oracle],input=json.dumps(cases),text=True))
lines=['import Base','import ../packages/runtime/test/object-delete.bend as T','import ../packages/runtime/test/object.bend as I','import ../packages/runtime/src/object.bend as O','import ../packages/runtime/src/value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,expect)in enumerate(zip(cases,expected,strict=True)):
 props='R.new(I.D())';symbols=[]
 for k,d in case['props']:
  if k[0]=='s':props=f'R.set(I.D(), {props}, {string(map(ord,k[1]))}, {descriptor(d)})'
  else:symbols.append(f'V.SymbolProperty{{{k[1]}, {descriptor(d)}}}')
 steps=[]
 for k,step in zip(case['deletes'],expect['steps'],strict=True):
  desc='None{}'if step['descriptor']is None else 'Some{'+descriptor(step['descriptor'])+'}'
  steps.append('T.Deletion{'+', '.join([key(k),flag(step['success']),listing([key(x)for x in step['keys']]),desc])+'}')
 lines += [f'def case{i}() -> IO(Unit):',f'  T.run({flag(case["array"])}, {expect["length"]}, {flag(case["writable"])}, {flag(case["extensible"])}, {props}, {listing(symbols)}, {listing(steps)})']
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()'for i in range(len(cases))]+[f'    IO.print("PASS {len(cases)} deletion sequences and {sum(len(c["deletes"])for c in cases)} mutation results")']
source=BUILD/'object-delete-vectors.bend';source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-object-delete'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=60)
