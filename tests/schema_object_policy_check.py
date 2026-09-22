"""Proposed literal-key semantics; differences await public-integration approval."""
import json, subprocess
from pathlib import Path
from schema_literals import value, string
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
cases=[{'policy':{'kind':'object','fields':[[declared,{'kind':'scalar','index':1},True]]},'value':{actual:'1'}} for declared,actual in [('a.b','axb'),('[x]','x')]]
reference=json.loads(subprocess.check_output(['node','tests/schema_builder_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/runtime/src/schema.bend as D','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/test/schema-convert.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for i,(case,result) in enumerate(zip(cases,reference,strict=True)):
    declared=case['policy']['fields'][0][0]; actual=next(iter(case['value']))
    assert result['converted']=={'object':[[actual,{'number':[1072693248,0]}]]}, result
    lines.append('    T.converted(D.convert(D.object(R.Record{R.Property{'+string(declared)+', D.optional(D.numberBuilder())} <> Nil{}}), '+value(case['value'])+'), '+value(case['value'])+', "proposed literal object keys '+str(i)+'")')
lines.append('    IO.print("PASS 2 proposed object-key differences, pending public integration")')
source=BUILD/'schema-object-policy.bend';source.write_text('\n'.join(lines)+'\n');output=BUILD/'schema-object-policy'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']: subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
