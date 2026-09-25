"""Local acyclic reference cases through the actual public validation path."""
import json
from pathlib import Path
import subprocess
from urllib.parse import quote
from schema_literals import value,string
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'build'
dependency=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dependency.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dependency.read_text())['version']=='1.3.27'
cases=[]
def case(schema,instance):
    cases.append({'schema':schema,'value':instance})
values=[None,False,True,0,1,1.5,'42','bad',[],[1],['bad'],{}, {'x':1},{'x':None}]
leaves=[{'type':t} for t in ['number','integer','string','boolean','null','array','object']]
leaves += [{'type':['number','null']},{'anyOf':[{'type':'number'},{'type':'null'}]},
           {'type':'array','items':{'type':'integer'}},
           {'type':'object','properties':{'x':{'type':'number'}},'required':['x']},
           {'minimum':2},False,True]
for leaf in leaves:
    for required in [[],['value']]:
        schema={'type':'object','properties':{'value':{'$ref':'#/$defs/t'}},'$defs':{'t':leaf},'required':required}
        for v in values:
            case(schema,{'value':v})
for key in ['a/b~c','space name','€','😀','~1','a+b','']:
    token=key.replace('~','~0').replace('/','~1')
    ref='#/'+quote('$defs/'+token,safe='/~')
    for v in values:
        case({'type':'object','properties':{'value':{'$ref':ref}},'$defs':{key:{'type':'integer'}}},{'value':v})
for v in values:
    case({'type':'object','properties':{'value':{'$ref':'#/definitions/a'}},
          'definitions':{'a':{'$ref':'#/definitions/b'},'b':{'type':['number','null']}}},{'value':v})
    case({'type':'object','properties':{'value':{'$ref':'#/$defs/t/allOf/0'}},
          '$defs':{'t':{'allOf':[{'type':'integer'}]}}},{'value':v})
    case({'type':'object','properties':{'value':{'$ref':'#/$defs/t','minimum':2}},
          '$defs':{'t':{'type':'integer'}}},{'value':v})
case({'type':'object','properties':{'a':{'$ref':'#/$defs/t'},'b':{'$ref':'#/$defs/t'}},'$defs':{'t':{'type':'integer'}}},{'a':'bad','b':'bad'})
case({'$ref':'#/$defs/missing'},{})
case({'$defs':{'unused':{'format':'email'}},'type':'object'},{})
# Exact upstream nullable-reference test.
case({'type':'object','properties':{'value':{'$ref':'#/$defs/value'}},'$defs':{'value':{'anyOf':[{'type':'number'},{'type':'null'}]}}},{'value':None})
expected=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/plain-validation.bend as T',
       'import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R',
       'import ../packages/runtime/src/f64.bend as F']
for i,(fixture,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):']
    args=f'{value(fixture["value"])}, {value(fixture["schema"])}'
    label=string(f'local reference {i}')
    if result['ok']:
        lines.append(f'  T.check({args}, {value(result["value"])}, {value(fixture["value"])}, {label})')
    else:
        assert result['message'].startswith('Validation failed'),result
        lines.append(f'  T.reject({args}, {value(fixture["value"])}, {string(result["message"])}, {label})')
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]
lines.append(f'    IO.print("PASS {len(cases)} local-reference validation outcomes and exact failure messages")')
source=BUILD/'schema-references-check.bend';source.write_text('\n'.join(lines)+'\n')
for source,name in [(source,'schema-references-check'),('packages/runtime/test/schema-load.bend','schema-reference-errors'),('packages/ai/test/plain-validation-cases-upstream.bend','plain-validation-cases-upstream')]:
    output=BUILD/name
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
