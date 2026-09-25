"""Compare ordered schema-type selection with the actual source block."""
import json
from pathlib import Path
import subprocess
from schema_test_values import valid, bend
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
values=[['null'],['boolean',False],['boolean',True],['array',[['null']]],['object',[],[]]]
values += [['number',raw] for raw in ['0000000000000000','8000000000000000','3ff0000000000000','3ff8000000000000','7ff8000000000001','7ff0000000000000']]
values += [['string',list(map(ord,text))] for text in ['',' ','0','1','1.5','true','false','Infinity','-0','0x10']]
types=[[],['number'],['integer'],['boolean'],['string'],['null'],['unknown'],['number','string'],['string','number'],['number','null'],['null','number'],['integer','number'],['integer','boolean'],['boolean','integer'],['null','boolean','number'],['unknown','number','string'],['number','number'],['array','number'],['object','string'],['unknown','string'],['boolean','string'],['string','boolean']]
# JS-only dynamic values are intentionally outside the Bend API.
values = [v for v in values if valid(v)]
expected=json.loads(subprocess.check_output(['node','tests/schema_type_coercion_reference.mjs'],input=json.dumps(dict(values=values,types=types)),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/primitive-coercion.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B','import ../packages/runtime/src/record.bend as R']
for i,(value,results) in enumerate(zip(values,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  do IO<Unit>:']
    for j,(kinds,result) in enumerate(zip(types,results,strict=True)):
        items=' <> '.join([json.dumps(kind) for kind in kinds]+['Nil{}'])
        lines.append(f'    T.checkTypes({bend(value)}, {items}, {bend(result)}, "type coercion {i}/{j}")')
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(values))]+[f'    IO.print("PASS {len(values)*len(types)} upstream schema-type coercion cases")']
source=BUILD/'schema-type-coercion-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-schema-type-coercion'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
