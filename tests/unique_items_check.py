"""Native structural uniqueness with the approved signed-zero adaptation."""
from upstream_pin import check_sibling
check_sibling()
import json,subprocess
from pathlib import Path
from schema_literals import value,string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
values=[[],[None],[None,None],[1,1],[1,2],[True,1],[False,0],['1',1],['x','x'],[{},{}],
        [{'a':1,'b':2},{'b':2,'a':1}],[{'a':1},{'a':2}],[[1,2],[2,1]],[[1,2],[1,2]],
        [[0],[0]],{'value':'not an array'},None,'x',list(range(40)),list(range(40))+[0]]
cases=[]
for enabled in [True,False]:
    for required_type in [False,True]:
        leaf={'uniqueItems':enabled}
        if required_type:leaf['type']='array'
        schema={'type':'object','properties':{'value':leaf},'required':['value']}
        for v in values:cases.append({'schema':schema,'value':{'value':v}})
for leaf,v in [({'type':'array','minItems':4,'maxItems':1,'uniqueItems':True},[1,1]),
               ({'type':'array','items':{'type':'number'},'uniqueItems':True},['1',1])]:
    cases.append({'schema':{'type':'object','properties':{'value':leaf},'required':['value']},'value':{'value':v}})
expected=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/plain-validation.bend as T','import ../packages/ai/test/validation-errors.bend as E',
       'import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(fixture,result) in enumerate(zip(cases,expected,strict=True)):
    args=f'{value(fixture["value"])}, {value(fixture["schema"])}';label=string(f'unique case {i}')
    lines.append(f'def case{i}() -> IO(Unit):')
    if result['ok']:lines.append(f'  T.check({args}, {value(result["value"])}, {value(fixture["value"])}, {label})')
    else:lines.append(f'  T.reject({args}, {value(fixture["value"])}, {string(result["message"])}, {label})')
# These are explicitly approved differences, not counted as upstream matches.
schema={'type':'object','properties':{'value':{'type':'array','uniqueItems':True}},'required':['value']}
changed=[{'schema':schema,'value':{'value':[0,-0.0]}},{'schema':schema,'value':{'value':[{'x':0},{'x':-0.0}]}}]
upstream=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(changed),text=True,cwd=ROOT))
assert all(result['ok'] for result in upstream), 'recheck signed-zero adaptation against changed upstream behavior'
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]
for c in changed:
    normalized={'value':[0,0]} if isinstance(c['value']['value'][0],int) else {'value':[{'x':0},{'x':0}]}
    message='Validation failed for tool "echo":\n  - value: must not have duplicate items\n\nReceived arguments:\n'+json.dumps(normalized,indent=2)
    lines.append(f'    E.validated("echo", {value(schema)}, {value(c["value"])}, {string(message)})')
lines.append(f'    IO.print("PASS {len(cases)} uniqueness comparisons and 2 approved signed-zero differences")')
source=BUILD/'unique-items-check.bend';source.write_text('\n'.join(lines)+'\n');output=BUILD/'unique-items-check'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
