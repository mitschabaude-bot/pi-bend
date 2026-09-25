"""Conditional checking and complete Pi diagnostics, including nested branches."""
from upstream_pin import check_sibling
check_sibling()
import json, subprocess
from pathlib import Path
from schema_literals import value, string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
values=[None,False,True,0,1,3,-1,'3','x',[],[1],['x'],{}, {'kind':'a'}, {'kind':'b'}, {'n':1}, {'n':'1'}, {'kind':'a','n':3}]
conditions=[True,False,{'type':'number'},{'minimum':2},{'required':['kind']},{'properties':{'kind':{'const':'a'}}}]
branches=[{}, {'then':False}, {'else':False}, {'then':{'minimum':2},'else':{'type':'string'}}, {'then':{'required':['n']},'else':{'type':'object','additionalProperties':False}}, {'then':{'type':'array','items':{'type':'number'}},'else':{'not':{'type':'number'}}}]
schemas=[{'if':condition,**branch} for condition in conditions for branch in branches]
schemas += [
 {'then':False,'else':False},
 {'if':{'type':'number'},'then':{'if':{'minimum':0},'then':{'multipleOf':2},'else':False},'else':{'if':{'type':'array'},'then':{'minItems':2},'else':False}},
 {'if':{'type':'number'},'then':False,'not':True,'anyOf':[False,False],'allOf':[False]},
 {'type':'number','if':{'minimum':2},'then':{'maximum':4},'else':False},
 {'anyOf':[{'if':True,'then':False},{'type':'number'}]},
 {'oneOf':[{'if':False,'else':False},{'type':'number'}]},
]
cases=[{'schema':{'type':'object','properties':{'value':schema},'required':['value']},'value':{'value':v}} for schema in schemas for v in values]
for item in values:
    cases.append({'schema':{'type':'object','$defs':{'number':{'type':'number'},'positive':{'minimum':0}},'properties':{'value':{'if':{'$ref':'#/$defs/number'},'then':{'$ref':'#/$defs/positive'},'else':False}},'required':['value']},'value':{'value':item}})
expected=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/plain-validation.bend as T','import ../packages/runtime/test/schema-load.bend as LoadTest','import ../packages/runtime/src/schema.bend as L','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    original=value(case['value']);args=f'{original}, {value(case["schema"])}'
    expression=f'T.check({args}, {value(result["value"])}, {original}, "conditional {i}")' if result['ok'] else f'T.reject({args}, {original}, {string(result["message"])}, "conditional {i}")'
    lines += [f'def case{i}() -> IO(Unit):','  '+expression]
malformed=[({'if':7},'if'),({'if':True,'then':{'type':7}},'then/type'),({'if':True,'else':{'type':7}},'else/type'),({'properties':{'x':{'if':{},'then':7}}},'properties/x/then')]
for i,(schema,path) in enumerate(malformed,len(cases)):
    lines += [f'def case{i}() -> IO(Unit):',f'  LoadTest.invalid(L.compile({value(schema)}), {string(path)})']
count=len(cases)+len(malformed);groups=[]
for start in range(0,count,60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,count))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} conditional outcomes/exact messages and {len(malformed)} malformed-schema paths")']
src=BUILD/'schema-conditional-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'schema-conditional-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
