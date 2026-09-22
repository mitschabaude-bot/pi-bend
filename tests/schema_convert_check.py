"""Builder scalar conversion, distinct from pi's plain-schema coercion."""
import json, math, random, struct, subprocess
from pathlib import Path
from schema_literals import value,string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists():
    subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
values=[None,True,False,0,-0.0,1,-1,2,-2,0.5,-0.5,1.9,-1.9,5e-324,-5e-324,1e100,-1e100,
        '', ' ', '\t\n', 'true','false','TRUE','FALSE','TrUe',' true ',' true','false ',
        'null','NULL','undefined','UNDEFINED','0','1','-1','1.9','-0.5','-0','-0.0','+0','001',
        '0x10','0b101','0o10','1e2','1e309','Infinity','-Infinity','NaN','bad',
        '0n','-0n','1n','-1n','9007199254740991n','-9007199254740991n','9007199254740992n',
        '-9007199254740992n','0001n','01n','+1n',' 1n','1n ','1.5n','1e2n','n','-n',
        '9'*400+'n','9'*400,'NaNn','\0',[],[1],['1'],{}, {'value':'1'},'😀','\u00a0', '\ufeff']
cases=[{'kind':kind,'value':v} for kind in range(5) for v in values]
rng=random.Random(831)
for _ in range(600):
    bits=rng.getrandbits(64)
    v=struct.unpack('>d',bits.to_bytes(8,'big'))[0]
    if math.isfinite(v): cases.append({'kind':2,'value':v})
for exponent in [0,1,1022,1023,1024,1073,1074,1075,2046]:
    for sign in [0,1]:
        for fraction in [0,1,(1<<51),(1<<52)-1]:
            bits=(sign<<63)|(exponent<<52)|fraction
            cases.append({'kind':2,'value':struct.unpack('>d',bits.to_bytes(8,'big'))[0]})
expected=json.loads(subprocess.check_output(['node','tests/schema_convert_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
names=['ToBoolean','ToNumber','ToInteger','ToString','ToNull']
lines=['import Base','import ../packages/runtime/test/schema-convert.bend as T','import ../packages/runtime/src/schema.bend as C',
       'import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    expected_value=('V.Number{F.fromBits('+', '.join(map(str,result['bits']))+')}' if 'bits' in result else value(result['value']))
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check(C.{names[case["kind"]]}{{}}, {value(case["value"])}, {expected_value}, {string("builder scalar "+str(i))})']
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]
lines.append(f'    IO.print("PASS {len(cases)} builder scalar conversions, with exact binary64 results")')
source=BUILD/'schema-convert-check.bend';source.write_text('\n'.join(lines)+'\n')
for source,name in [(source,'schema-convert-check'),('packages/runtime/test/schema-convert.bend','schema-convert-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
