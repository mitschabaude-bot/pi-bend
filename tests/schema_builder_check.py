"""Builder wire declarations, compiled constraints and conversion projections."""
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
def union(*p): return dict(kind='union',items=list(p))
def literal(v): return dict(kind='literal',value=v)
policies=[dict(kind='preserve'),dict(kind='never'),tuple_(),union()]
for i in range(5):
    p=scalar(i)
    policies += [p,array(p),tuple_(p),union(p),union(p,scalar(4)),union(scalar(4),p)]
policies += [literal(x) for x in [True,False,0,-0.0,1,1.5,'','x']]
policies += [array(union(scalar(1),scalar(4))),tuple_(scalar(1),array(scalar(0))),union(tuple_(scalar(1),scalar(1)),tuple_(scalar(3),scalar(0))),union(array(scalar(1)),array(scalar(0)))]
values=[None,False,True,0,-0.0,1,'1','-0','true','bad',[],['1'],['1','true'],['1','bad'],[1,None],[['true']],{}, {'x':1}]
cases=[dict(policy=p,value=v) for p in policies for v in values]
expected=json.loads(subprocess.check_output(['node','tests/schema_builder_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
def seq(items): return ''.join(x+' <> ' for x in items)+'Nil{}'
def declaration(p):
    k=p['kind']
    if k=='never': return 'D.never()'
    if k=='scalar': return 'D.'+['boolean','number','integer','string','null'][p['index']]+'()'
    if k=='array': return 'D.array('+declaration(p['item'])+')'
    if k in ['union','tuple']: return 'D.'+k+'('+seq(declaration(x) for x in p['items'])+')'
    if k=='literal':
        v=p['value']
        if isinstance(v,bool): arg='C.BooleanLiteral{'+('True{}' if v else 'False{}')+'}'
        elif isinstance(v,(int,float)): arg='C.NumberLiteral{'+value(v)[len('V.Number{'):-1]+'}'
        else: arg='C.StringLiteral{'+string(v)+'}'
        return 'D.literal('+arg+')'
    return 'D.unknown()'
def decoded(v):
    if 'number' in v: return 'V.Number{F.fromBits('+', '.join(map(str,v['number']))+')}'
    if 'array' in v: return 'V.ArrayValue{'+seq(decoded(x) for x in v['array'])+'}'
    if 'object' in v: return 'V.ObjectValue{R.Record{'+seq('R.Property{'+string(k)+', '+decoded(x)+'}' for k,x in v['object'])+'}}'
    return value(v['scalar'])
lines=['import Base','import ../packages/runtime/test/schema-builder.bend as T','import ../packages/runtime/src/schema-builder.bend as D','import ../packages/runtime/src/schema-convert.bend as C','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,e) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({declaration(c["policy"])}, {value(c["value"])}, {value(e["schema"])}, {decoded(e["converted"])}, '+('True{}' if e['valid'] else 'False{}')+f', "builder {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} builder declarations, checks and conversions")']
source=BUILD/'schema-builder-check.bend';source.write_text('\n'.join(lines)+'\n')
for src,name in [(source,'schema-builder-check'),('packages/runtime/test/schema-builder.bend','schema-builder-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(src),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']: subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
