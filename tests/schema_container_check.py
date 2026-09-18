"""Immutable builder container, literal and union policies against pinned TypeBox conversion."""
import json, subprocess
from pathlib import Path
from schema_literals import value, string
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
def scalar(i): return dict(kind='scalar',index=i)
def array(p, **options): return dict(kind='array',item=p,options=options)
def literal(v): return dict(kind='literal',value=v)
def union(*p): return dict(kind='union',items=list(p))
def tuple_(*p): return dict(kind='tuple',items=list(p))
policies=[dict(kind='preserve'),tuple_()]
for i in range(5):
    p=scalar(i)
    policies += [array(p),array(array(p)),tuple_(p),tuple_(p,scalar((i+1)%5)),tuple_(array(p),p),array(tuple_(p,scalar((i+1)%5)))]
policies += [tuple_(tuple_(scalar(1),scalar(0)),array(scalar(2)),scalar(3))]
values=[None,False,True,0,-0.0,1,'1','-0','1.9','true','bad',{}, {'x':'1'},[],['1'],['1','false','extra'],[['1'],['2','3']],[[['-0']]],['-0','-0.5',None],[[1,'false'],['1.5','-0.5'],False,'extra']]
cases=[dict(policy=p,value=v) for p in policies for v in values]
union_policies=[union(),union(scalar(1)),union(scalar(1),scalar(3)),union(scalar(3),scalar(1)),
    union(scalar(1),scalar(4)),union(scalar(4),scalar(1)),
    union(array(scalar(1),minItems=2),tuple_(scalar(1))),
    union(tuple_(scalar(1),scalar(1)),tuple_(scalar(3),scalar(0))),
    union(array(scalar(1)),array(scalar(0))),
    array(union(scalar(1),scalar(4))),tuple_(union(scalar(1),scalar(3)),union(scalar(0),scalar(4))),
    union(union(literal(1),literal(True)),scalar(4)),
    union(literal('1'),literal(2),literal(False))]
union_values=values+[['1','true'],['bad','false'],['1','bad'],['true','2'],['true','false'],['1',None],2,'2','FALSE','NULL','0n','-0.5',0.5]
for p in union_policies: cases += [dict(policy=p,value=v) for v in union_values]
for v in [True,False,0,-0.0,1,-1,1.5,'','true','false','0','1','null']:
    cases += [dict(policy=literal(v),value=x) for x in union_values]

expected=json.loads(subprocess.check_output(['node','tests/schema_container_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
names=['ToBoolean','ToNumber','ToInteger','ToString','ToNull']
def policy(p):
    if p['kind']=='literal':
        v=p['value']
        if isinstance(v,bool): arg='C.BooleanLiteral{'+('True{}' if v else 'False{}')+'}'
        elif isinstance(v,(int,float)): arg='C.NumberLiteral{'+value(v)[len('V.Number{'):-1]+'}'
        else: arg='C.StringLiteral{'+string(v)+'}'
        return 'C.Literal{'+arg+'}'
    if p['kind']=='union': return 'C.Union{'+''.join('C.Branch{'+schema(x)+', '+policy(x)+'} <> ' for x in p['items'])+'Nil{}}'
    if p['kind']=='scalar': return 'C.Scalar{C.'+names[p['index']]+'{}}'
    if p['kind']=='array': return 'C.ArrayItems{'+policy(p['item'])+'}'
    if p['kind']=='tuple': return 'C.TupleItems{'+''.join(policy(x)+' <> ' for x in p['items'])+'Nil{}}'
    return 'C.Preserve{}'
def seq(items): return ''.join(x+' <> ' for x in items)+'Nil{}'
def schema(p):
    k=p['kind']
    if k=='scalar': return 'S.JsonKind{S.'+['BooleanType','NumberType','IntegerType','StringType','NullType'][p['index']]+'{}}'
    if k=='literal': return 'S.Constant{'+value(p['value'])+'}'
    if k=='union': return 'S.Any{'+seq(schema(x) for x in p['items'])+'}'
    if k=='array':
        terms=['S.JsonKind{S.ArrayType{}}','S.Array{Nil{}, '+schema(p['item'])+'}']
        if 'minItems' in p.get('options',{}): terms += ['S.ItemCount{S.CountBounds{B.fromU32('+str(p['options']['minItems'])+'), None{}}}']
        return 'S.All{'+seq(terms)+'}'
    if k=='tuple':
        n=str(len(p['items']))
        return 'S.All{S.JsonKind{S.ArrayType{}} <> S.ItemCount{S.CountBounds{B.fromU32('+n+'), Some{B.fromU32('+n+')}}} <> S.Array{'+seq(schema(x) for x in p['items'])+', S.Reject{}} <> Nil{}}'
    return 'S.Accept{}'
def decoded(v):
    if 'number' in v: return 'V.Number{F.fromBits('+', '.join(map(str,v['number']))+')}'
    if 'array' in v: return 'V.ArrayValue{'+''.join(decoded(x)+' <> ' for x in v['array'])+'Nil{}}'
    if 'object' in v: return 'V.ObjectValue{R.Record{'+''.join('R.Property{'+string(k)+', '+decoded(x)+'} <> ' for k,x in v['object'])+'Nil{}}}'
    return value(v['scalar'])
lines=['import Base','import ../packages/runtime/test/schema-convert.bend as T','import ../packages/runtime/src/schema-convert.bend as C','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/schema.bend as S','import ../packages/runtime/src/big-nat.bend as B']
for i,(c,e) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  T.converted(C.apply({policy(c["policy"])}, {value(c["value"])}), {decoded(e)}, "builder container {i}")']
groups=[]
for start in range(0,len(cases),80):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+80,len(cases)))]
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} builder container/literal/union conversions")']
source=BUILD/'schema-container-check.bend';source.write_text('\n'.join(lines)+'\n');output=BUILD/'schema-container-check'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']: subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
