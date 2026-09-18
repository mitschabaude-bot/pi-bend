"""Ordinary descriptor decisions and mutations versus Reflect.defineProperty."""
import json
from pathlib import Path
import subprocess
from schema_test_values import bend as schema_bend, string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
def val(tag):return schema_bend(tag)
def flag(x):return 'True{}'if x else 'False{}'
def accessor(x):return 'None{}'if x is None else f'Some{{{x}}}'
def descriptor(d):
 if d is None:return 'None{}'
 if 'value'in d:out='V.DataProperty{'+', '.join([val(d['value'])]+[flag(d[k])for k in ['writable','enumerable','configurable']])+'}'
 else:out='V.AccessorProperty{'+', '.join([accessor(d['get']),accessor(d['set']),flag(d['enumerable']),flag(d['configurable'])])+'}'
 return 'Some{'+out+'}'
def definition(d):
 fields=[]
 for k in ['value','writable','get','set','enumerable','configurable']:
  if k not in d:fields.append('None{}')
  else:fields.append('Some{'+(val(d[k])if k=='value'else accessor(d[k])if k in ['get','set']else flag(d[k]))+'}')
 return 'D.Definition{'+', '.join(fields)+'}'
def key(k):return 'O.StringKey{'+string(map(ord,k[1]))+'}'if k[0]=='s'else f'O.SymbolKey{{{k[1]}}}'
nums=[['number',s]for s in ['0000000000000000','8000000000000000','7ff8000000000001','7ff8000000000002','3ff0000000000000']]
current=[None]
for conf in [False,True]:
 for enum in [False,True]:
  for writable in [False,True]:current.append(dict(value=nums[0],writable=writable,enumerable=enum,configurable=conf))
 for getter in [None,1]:current.append(dict(get=getter,set=None,enumerable=False,configurable=conf))
current += [dict(value=n,writable=False,enumerable=False,configurable=False)for n in nums[1:]]
updates=[{},dict(value=['undefined']),dict(value=['null'])]+[dict(value=n)for n in nums]
for field in ['writable','enumerable','configurable']:
 for b in [False,True]:updates.append({field:b})
for field in ['get','set']:
 for fn in [None,1,2]:updates.append({field:fn})
updates += [dict(value=nums[4],writable=True,enumerable=True,configurable=True),dict(get=1,set=2,enumerable=True,configurable=True),dict(value=['undefined'],get=None),dict(writable=False,set=None)]
cases=[dict(current=c,update=u,extensible=e,key=k)for c in current for u in updates for e in [False,True]for k in [['s','x'],['y',3]]]
oracle='''let text='';for await(const s of process.stdin)text+=s;
const funcs={1:()=>{},2:()=>{}};
function build(v){switch(v[0]){case 'undefined':return undefined;case 'null':return null;case 'number':return Buffer.from(v[1],'hex').readDoubleBE();}}
function wire(v){if(v===undefined)return ['undefined'];if(v===null)return ['null'];const b=Buffer.alloc(8);b.writeDoubleBE(v);return ['number',b.toString('hex')];}
function desc(d){if(!d)return null;const o={...d};if('value'in o)o.value=build(o.value);for(const k of ['get','set'])if(k in o)o[k]=funcs[o[k]];return o;}
function encode(d){if(!d)return null;const o={...d};if('value'in o)o.value=wire(o.value);for(const k of ['get','set'])if(k in o)o[k]=o[k]===undefined?null:o[k]===funcs[1]?1:2;return o;}
console.log(JSON.stringify(JSON.parse(text).map(c=>{const o={before:undefined,2:undefined,[Symbol.for('9')]:undefined};const k=c.key[0]==='s'?c.key[1]:Symbol.for(String(c.key[1]));if(c.current)Object.defineProperty(o,k,desc(c.current));o.after=undefined;o[Symbol.for('10')]=undefined;if(!c.extensible)Object.preventExtensions(o);let status;try{status=String(Reflect.defineProperty(o,k,desc(c.update)))}catch(e){if(!(e instanceof TypeError))throw e;status='invalid'}return{status,descriptor:encode(Object.getOwnPropertyDescriptor(o,k)),keys:Reflect.ownKeys(o).map(k=>typeof k==='symbol'?['y',Number(Symbol.keyFor(k))]:['s',k])}})));'''
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',oracle],input=json.dumps(cases),text=True))
lines=['import Base','import ../packages/runtime/test/object-define.bend as T','import ../packages/runtime/src/object.bend as O','import ../packages/runtime/src/descriptor.bend as D','import ../packages/runtime/src/value.bend as V','import ../packages/runtime/src/f64.bend as F']
for i,(c,e)in enumerate(zip(cases,expected,strict=True)):
 keys=' <> '.join([key(k)for k in e['keys']]+['Nil{}'])
 lines += [f'def case{i}() -> IO(Unit):',f'  T.run({key(c["key"])}, {flag(c["extensible"])}, {descriptor(c["current"])}, {definition(c["update"])}, "{e["status"]}", {descriptor(e["descriptor"])}, {keys})']
# Keep each generated IO syntax tree bounded without dropping any cases.
groups=list(range(0,len(cases),64))
for group,start in enumerate(groups):
 lines += [f'def group{group}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()'for i in range(start,min(start+64,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    group{i}()'for i in range(len(groups))]+['    T.aliases()',f'    IO.print("PASS {len(cases)} ordinary property definitions and shared-value identity")']
source=BUILD/'object-define-vectors.bend';source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-object-define'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
