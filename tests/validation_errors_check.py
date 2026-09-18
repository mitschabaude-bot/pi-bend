"""Exact rendering comparisons; native issue collection remains separate."""
import json
from pathlib import Path
import subprocess
from schema_literals import value, seq, string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
dependency=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dependency.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dependency.read_text())['version']=='1.3.27'
cases=[]
def case(schema, received, name='echo'):
    cases.append({'schema':schema,'value':received,'name':name})
for t,received in [('boolean','1'),('boolean','0'),('null','null'),('integer','42.1')]:
    case({'type':'object','properties':{'value':{'type':t}},'required':['value']},{'value':received})
case({'type':'object','properties':{'x':{'type':'number'}},'required':['x','y'],'additionalProperties':False},{'x':'bad','z':1})
case({'type':'object','properties':{'nested':{'type':'object','required':['a','b']}}},{'nested':{}})
case({'type':'object','properties':{'items':{'type':'array','items':{'type':'integer'}}}},{'items':['bad','42.1']})
case({'type':'object','properties':{'value':{'anyOf':[{'type':'number'},{'type':'boolean'}]}}},{'value':'bad'})
case({'type':'object','properties':{'value':{'oneOf':[{'type':'number'},{'type':'integer'}]}}},{'value':1})
case({'type':'object','properties':{'value':{'minimum':2,'maximum':0}}},{'value':1}, 'tool "quoted"')
case({'type':'object','properties':{'a/b':{'type':'integer'},'a.b':{'type':'integer'}}},{'a/b':'bad','a.b':'bad'})
case({'type':'object','required':['']},{})
paths=[]
for path in ['', '/', '/value', '/items/0/name', '//x', 'unrooted/path', '/a~1b/x.y']:
    paths.append({'keyword':'type','instancePath':path,'params':{}})
    for missing in [[], ['x'], ['x','y'], [''], ['a/b']]:
        paths.append({'keyword':'required','instancePath':path,'params':{'requiredProperties':missing}})
values=[None,True,False,0,-0.0,1.5,1e-7,1e21,'','quote"\\\n', '😀', '\b\f\0', 'literal \\u0000', [], {}, [[],{},[1,2]],
        {'array':[1,{'nested':[None,True]}], 'empty':{}, 'text':'hello\nworld'},
        {'a/b':{'~key':'x'},'arr':['a','b']}]
for n in range(1,30):
    values.append({'index':n,'items':[{'value':str(i),'present':bool(i%2)} for i in range(n%6)]})
result=json.loads(subprocess.check_output(['node','tests/validation_errors_reference.mjs'],input=json.dumps({'cases':cases,'paths':paths,'values':values}),text=True,cwd=ROOT))
def location(error):
    p=string(error['instancePath'])
    if error['keyword']=='required':
        return 'E.Required{'+p+', '+seq(map(string,error['params'].get('requiredProperties',[])))+'}'
    return 'E.Instance{'+p+'}'
lines=['import Base','import ../packages/ai/test/validation-errors.bend as T',
       'import ../packages/ai/src/utils/validation-errors.bend as E',
       'import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R',
       'import ../packages/runtime/src/f64.bend as F','def main() -> IO(Unit):','  do IO<Unit>:']
for fixture,expected in zip(cases,result['messages'],strict=True):
    issues=seq('E.Issue{'+location(issue)+', '+string(issue['message'])+'}' for issue in expected['issues'])
    lines.append(f'    T.message({string(fixture["name"])}, {value(fixture["value"])}, {issues}, {string(expected["message"])})')
for error,expected in zip(paths,result['paths'],strict=True):
    lines.append(f'    T.path({location(error)}, {string(expected)})')
for v,expected in zip(values,result['pretty'],strict=True):
    lines.append(f'    T.pretty({value(v)}, {string(expected)})')
lines.append(f'    IO.print("PASS {len(cases)} exact validation messages, {len(paths)} paths and {len(values)} indented JSON values")')
source=BUILD/'validation-errors-check.bend'
source.write_text('\n'.join(lines)+'\n')
for source,name in [(source,'validation-errors-check'),('packages/ai/test/validation-errors.bend','validation-errors-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
