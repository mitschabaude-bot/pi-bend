"""Composed multipleOf validation and exact diagnostics against pinned Pi."""
import json, math, subprocess
from pathlib import Path
from schema_literals import value, string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
divisors=[0,-0.0,-2,2,3,.1,.2,.3,1e-10,1e-11,1e-300,5e-324,1e300]
values=[None,False,True,'3','bad',[],{},0,-0.0,1,-1,2,3,.3,.6,.7,1e-10,math.nextafter(1e-10,0),math.nextafter(1e-10,math.inf),-1e-10,1e-300,5e-324,1e300,1.7976931348623157e308]
cases=[]
for divisor in divisors:
    for typed in [False,True]:
        inner={'multipleOf':divisor,**({'type':'number'} if typed else {})}
        for item in values:
            cases.append({'schema':{'type':'object','properties':{'value':inner},'required':['value']},'value':{'value':item}})
# All numeric failures together verify diagnostic order independent of key order.
cases.append({'schema':{'type':'object','properties':{'value':{'multipleOf':2,'maximum':1,'minimum':2,'exclusiveMinimum':3,'exclusiveMaximum':0,'type':'number'}}},'value':{'value':1.5}})
expected=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/plain-validation.bend as T','import ../packages/ai/src/utils/validation.bend as Validation','import ../packages/ai/src/types.bend as Ai','import ../packages/runtime/test/schema-builder.bend as BuilderTest','import ../packages/runtime/src/schema-builder.bend as D','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    original=value(case['value']);args=f'{original}, {value(case["schema"])}'
    expression=f'T.check({args}, {value(result["value"])}, {original}, "multiple {i}")' if result['ok'] else f'T.reject({args}, {original}, {string(result["message"])}, "multiple {i}")'
    lines += [f'def case{i}() -> IO(Unit):','  '+expression]
# Builder options must reach the same executable constraint and wire projection.
builders=[{'policy':{'kind':'scalar','index':1,'options':{'multipleOf':d}},'value':v} for d in divisors for v in [0,1,3,.3,'3']]
reference=json.loads(subprocess.check_output(['node','tests/schema_builder_reference.mjs'],input=json.dumps(builders),text=True,cwd=ROOT))
for i,(case,result) in enumerate(zip(builders,reference,strict=True),len(cases)):
    options=value(case['policy']['options'])[len('V.ObjectValue{'):-1]
    converted=result['converted']
    if 'number' in converted:output='V.Number{F.fromBits('+', '.join(map(str,converted['number']))+')}'
    else:output=value(converted['scalar'])
    lines += [f'def case{i}() -> IO(Unit):',f'  BuilderTest.configured(D.withOptions(D.number(), {options}), {value(case["value"])}, {value(result["schema"])}, {output}, '+('True{}' if result['valid'] else 'False{}')+f', "multiple builder {i}")']
count=len(cases)+len(builders)
for i,bad in enumerate([None,True,'2',[],{}],count):
    lines += [f'def case{i}() -> IO(Unit):',f'  T.schemaFailure(Validation.validatePlainToolArguments(Ai.Tool{{"echo", "", {value({"multipleOf":bad})}, None{{}}}}, Ai.ToolCall{{"id", "echo", V.Null{{}}, None{{}}, None{{}}}}))']
count+=5;groups=[]
for start in range(0,count,60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,count))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} multipleOf outcomes/messages, {len(builders)} builder cases and 5 malformed-schema rejections")']
src=BUILD/'schema-multiple-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'schema-multiple-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
