"""Strict provider schemas, fallback policy and exact error precedence from Pi."""
from upstream_pin import check_sibling
check_sibling()
import json,random,subprocess
from pathlib import Path
from schema_literals import value,string,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
obj=lambda fields,**kw:dict(type='object',properties=fields,**kw)
primitives=[{}, {'type':'string'}, {'type':'number'}, {'type':'boolean'}, {'type':'null'}, {'type':['string','null']}, {'const':None}, {'enum':[1,None]}, {'anyOf':[{'type':'string'},{'type':'null'}]}, {'anyOf':[{'type':'string'},{'type':'number'}]}]
cases=[None,False,True,0,'object',[],{}, {'type':'string'}, {'type':['object','null']}, {'type':'object'},obj({}),obj({'path':{'type':'string'},'offset':{'type':'number'},'metadata':obj({'enabled':{'type':'boolean'}}),'nullable':{'anyOf':[{'type':'string'},{'type':'null'}]}},required=['path','metadata'])]
for schema in primitives:
    for required in [[],['value']]:cases.append(obj({'value':schema},required=required,title='kept',description='metadata'))
for key in ['$ref','$defs','definitions','allOf','oneOf','patternProperties','dependentSchemas','dependencies','unevaluatedProperties','propertyNames','contains','prefixItems','not','if','then','else']:
    for val in [None,False,{}]:
        schema={'type':'object',key:val};cases += [schema,obj({'child':schema})]
for bad in [None,False,True,1,'string',[],[{'type':'string'}]]:
    cases += [dict(type='object',properties=bad),obj({'value':bad}),dict(type='object',required=bad),dict(type='object',additionalProperties=bad),obj({'value':dict(type='array',items=bad)})]
for required in [[],['x'],['x','x'],['missing'],['x',False],['missing','x'],['x',1]]:cases.append(obj({'x':{'type':'string'}},required=required))
for union in [None,False,[],[False],[{'type':'array'}],[{'properties':{}}],[{'items':{}}],[{'type':['string','array']}],[{'type':'object','$ref':'ignored'}],[{'anyOf':[{'type':'object'}]}]]:
    cases.append(obj({'value':{'anyOf':union}}))
for schema in [obj({'required':{'type':'string'},'optional':{'type':'number'}},required=['required']), {'type':'array','items':{'type':'string'}}, {'type':'array','items':obj({'optional':{'type':'boolean'}})}]:
    cases.append(obj({'value':schema}))
# Competing errors verify traversal order: banned keys, unions, items, objects.
cases += [dict(type='string',properties={},items=False),dict(type='object',anyOf=[False],items=[]),dict(type='object',oneOf=[],allOf=[]),obj({'first':False,'second':{'$ref':'x'}},required=['missing']),dict(type='object',additionalProperties=True,properties=False,required=False)]
rng=random.Random(237)
for _ in range(55):
    fields={f'field{i}':rng.choice(primitives+[obj({'nested':rng.choice(primitives)}),{'type':'array','items':rng.choice(primitives)}]) for i in range(rng.randrange(1,5))}
    cases.append(obj(fields,required=[k for k in fields if rng.randrange(2)]))
results=json.loads(subprocess.check_output(['node','tests/strict_schema_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def result(r,fn):return 'Done{'+fn(r['value'])+'}' if r['ok'] else 'Fail{'+string(r['error'])+'}'
def resolution(v):
    assert v in [None,True]
    return 'None{}' if v is None else 'Some{True{}}'
lines=['import Base','import ../packages/ai/test/api/strict-json-schema.bend as Check','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(schema,expected) in enumerate(zip(cases,results,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+value(schema)+', '+result(expected['strict'],value)+', '+seq(result(r,resolution) for r in expected['resolutions'])+f', "strict schema {i}")']
groups=[]
for start in range(0,len(cases),25):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+25,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} strict schemas, {len(cases)*10} policy resolutions and schema parameter selection")']
src=BUILD/'strict-schema-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'strict-schema-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
