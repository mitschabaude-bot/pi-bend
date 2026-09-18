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
def object_(*fields): return dict(kind='object',fields=list(fields))
policies=[dict(kind='preserve'),dict(kind='never'),tuple_(),union()]
for i in range(5):
    p=scalar(i)
    policies += [p,array(p),tuple_(p),union(p),union(p,scalar(4)),union(scalar(4),p)]
policies += [literal(x) for x in [True,False,0,-0.0,1,1.5,'','x']]
policies += [array(union(scalar(1),scalar(4))),tuple_(scalar(1),array(scalar(0))),union(tuple_(scalar(1),scalar(1)),tuple_(scalar(3),scalar(0))),union(array(scalar(1)),array(scalar(0)))]
values=[None,False,True,0,-0.0,1,'1','-0','true','bad',[],['1'],['1','true'],['1','bad'],[1,None],[['true']],{}, {'x':1}]
cases=[dict(policy=p,value=v) for p in policies for v in values]
object_policies=[object_(),object_(('x',scalar(1),False)),object_(('x',scalar(1),True)),
    object_(('x',scalar(1),False),('flag',scalar(0),True)),
    object_(('x',union(scalar(1),scalar(4)),True)),
    object_(('x',array(scalar(1)),True)),
    object_(('x',object_(('flag',scalar(0),True)),False)),
    array(object_(('x',scalar(1),True))),
    union(object_(('x',literal(1),False)),object_(('x',scalar(0),False))),
    object_(('path',scalar(3),False),('offset',scalar(1),True),('nullable',union(scalar(3),scalar(4)),True),('metadata',object_(('enabled',scalar(0),True)),False))]
object_values=values+[{'x':'1'},{'x':None},{'x':'bad','extra':'2'},{'x':'1','flag':'TRUE'}, {'x':{'flag':'false'}},[{'x':'1'},{'x':None}], {'path':'file.txt','offset':None,'nullable':None,'metadata':{'enabled':None}}, {'flag':None}, {'extra':'1'}, {'x':['1','2']}, {'x':1}, {'x':True}]
for p in object_policies: cases += [dict(policy=p,value=v) for v in object_values]

option_policies=[
    dict(**union(tuple_(scalar(1)),array(scalar(1))),options={'minItems':2}),
    dict(**scalar(1),options={'minimum':1,'maximum':5}),
    dict(**scalar(1),options={'exclusiveMinimum':0,'exclusiveMaximum':2}),
    dict(**scalar(2),options={'minimum':0,'maximum':5}),
    dict(**scalar(3),options={'title':'Text','description':'Tool input','default':'x','examples':['x','y'],'deprecated':True,'readOnly':False,'writeOnly':True}),
    dict(**array(scalar(1)),options={'minItems':1,'maxItems':2,'uniqueItems':True}),
    dict(**array(scalar(1)),options={'uniqueItems':False}),
    dict(**tuple_(scalar(1)),options={'minItems':0}),
    dict(**object_(('x',scalar(1),True)),options={'additionalProperties':False}),
    dict(**object_(('x',scalar(1),True)),options={'minProperties':1,'maxProperties':1}),
    dict(**union(scalar(1),scalar(4)),options={'description':'Nullable number'}),
    dict(**literal(1),options={'description':'One'}),
    dict(kind='preserve',options={'default':None,'examples':[None,False,{'x':1}]}),
]
option_values=object_values+[2,5,6,0.5,1.5,[1,1],[1,2],[1,2,3],{'x':1,'y':2}]
for p in option_policies: cases += [dict(policy=p,value=v) for v in option_values]
expected=json.loads(subprocess.check_output(['node','tests/schema_builder_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
def seq(items): return ''.join(x+' <> ' for x in items)+'Nil{}'
def declaration(p):
    k=p['kind']
    if k=='object': return 'D.object(R.Record{'+seq('R.Property{'+string(key)+', D.'+('optional' if optional else 'required')+'('+declaration(child)+')}' for key,child,optional in p['fields'])+'})'
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
    expression=declaration(c['policy']); method='check'
    if 'options' in c['policy']:
        options=value(c['policy']['options'])[len('V.ObjectValue{'):-1]
        expression='D.withOptions('+expression+', '+options+')';method='configured'
    lines += [f'def case{i}() -> IO(Unit):',f'  T.{method}({expression}, {value(c["value"])}, {value(e["schema"])}, {decoded(e["converted"])}, '+('True{}' if e['valid'] else 'False{}')+f', "builder {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} builder declarations, checks and conversions")']
source=BUILD/'schema-builder-check.bend';source.write_text('\n'.join(lines)+'\n')
for src,name in [(source,'schema-builder-check'),('packages/runtime/test/schema-builder.bend','schema-builder-native'),('packages/runtime/test/schema-builder-options.bend','schema-builder-options-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(src),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']: subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
