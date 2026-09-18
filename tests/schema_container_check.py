"""Immutable builder array/tuple policies against pinned TypeBox conversion."""
import json, subprocess
from pathlib import Path
from schema_literals import value, string
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
def scalar(i): return dict(kind='scalar',index=i)
def array(p): return dict(kind='array',item=p)
def tuple_(*p): return dict(kind='tuple',items=list(p))
policies=[dict(kind='preserve'),tuple_()]
for i in range(5):
    p=scalar(i)
    policies += [array(p),array(array(p)),tuple_(p),tuple_(p,scalar((i+1)%5)),tuple_(array(p),p),array(tuple_(p,scalar((i+1)%5)))]
policies += [tuple_(tuple_(scalar(1),scalar(0)),array(scalar(2)),scalar(3))]
values=[None,False,True,0,-0.0,1,'1','-0','1.9','true','bad',{}, {'x':'1'},[],['1'],['1','false','extra'],[['1'],['2','3']],[[['-0']]],['-0','-0.5',None],[[1,'false'],['1.5','-0.5'],False,'extra']]
cases=[dict(policy=p,value=v) for p in policies for v in values]
expected=json.loads(subprocess.check_output(['node','tests/schema_container_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
names=['ToBoolean','ToNumber','ToInteger','ToString','ToNull']
def policy(p):
    if p['kind']=='scalar': return 'C.Scalar{C.'+names[p['index']]+'{}}'
    if p['kind']=='array': return 'C.ArrayItems{'+policy(p['item'])+'}'
    if p['kind']=='tuple': return 'C.TupleItems{'+''.join(policy(x)+' <> ' for x in p['items'])+'Nil{}}'
    return 'C.Preserve{}'
def decoded(v):
    if 'number' in v: return 'V.Number{F.fromBits('+', '.join(map(str,v['number']))+')}'
    if 'array' in v: return 'V.ArrayValue{'+''.join(decoded(x)+' <> ' for x in v['array'])+'Nil{}}'
    if 'object' in v: return 'V.ObjectValue{R.Record{'+''.join('R.Property{'+string(k)+', '+decoded(x)+'} <> ' for k,x in v['object'])+'Nil{}}}'
    return value(v['scalar'])
lines=['import Base','import ../packages/runtime/test/schema-convert.bend as T','import ../packages/runtime/src/schema-convert.bend as C','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,e) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  T.converted(C.apply({policy(c["policy"])}, {value(c["value"])}), {decoded(e)}, "builder container {i}")']
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]+[f'    IO.print("PASS {len(cases)} builder array/tuple conversions")']
source=BUILD/'schema-container-check.bend';source.write_text('\n'.join(lines)+'\n');output=BUILD/'schema-container-check'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']: subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
