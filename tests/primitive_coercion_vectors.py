"""Run original primitive coercion over tagged values without JSON erasure."""
from upstream_pin import check_sibling
check_sibling()
import json
from pathlib import Path
import random
import subprocess
from schema_test_values import valid, bend
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
kinds=['number','integer','boolean','string','null','object','array','unknown','','Number']
values=[['null'],['boolean',False],['boolean',True],['array',[]]]
for raw in ['0000000000000000','8000000000000000','0000000000000001','3ff0000000000000','bff0000000000000','4000000000000000','3ff8000000000000','7ff0000000000000','fff0000000000000','7ff8000000000001','7ff0000000000001','7fefffffffffffff','0010000000000000']:
    values.append(['number',raw])
for text in ['', ' ', '\u00a0', '\ufeff', '0','-0','+0','42','1.5','1e3','1e309','1e-999','-1e-999','Infinity','-Infinity','NaN','0x10','-0x10','true','false','True','False',' true','false ','null','undefined','1_000','2.4703282292062327e-324','9007199254740993','\ud800','１']:
    values.append(['string',list(map(ord,text))])
rng=random.Random(85118)
for _ in range(32):values.append(['number',f'{rng.getrandbits(64):016x}'])
# JS-only dynamic values are intentionally outside the Bend API.
values = [v for v in values if valid(v)]
expected=json.loads(subprocess.check_output(['node','tests/primitive_coercion_reference.mjs'],input=json.dumps(dict(values=values,kinds=kinds)),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/primitive-coercion.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B','import ../packages/runtime/src/record.bend as R']
for i,(value,results) in enumerate(zip(values,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  do IO<Unit>:']
    for kind,result in zip(kinds,results,strict=True):
        lines.append(f'    T.check({bend(value)}, {json.dumps(kind)}, {bend(result)}, "coercion {i} {kind}")')
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(values))]+[f'    IO.print("PASS {len(values)*len(kinds)} upstream primitive coercion cases")']
source=BUILD/'primitive-coercion-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-primitive-coercion'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=180)
