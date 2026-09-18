"""Compare shared runtime scalar equality with JavaScript strict equality."""
import json
from pathlib import Path
import subprocess
from schema_test_values import bend as schema_bend
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
values=[['undefined'],['null'],['boolean',False],['boolean',True]]
values += [['number',raw] for raw in ['0000000000000000','8000000000000000','3ff0000000000000','bff0000000000000','7ff8000000000001','7ff0000000000000','fff0000000000000']]
values += [['string',points] for points in [[],[48],[49],[0x1f600],[0xd83d,0xde00],[0xd800],[0xdfff]]]
values += [['symbol',1],['symbol',2],['callable',1],['callable',2],['bigint',False,0],['bigint',True,0],['bigint',False,1],['bigint',True,1]]
def bend(v):
    if v[0]=='bigint':return 'V.BigInteger{'+('True{}' if v[1] else 'False{}')+f', B.fromU32({v[2]})'+'}'
    return schema_bend(v)
oracle='''let input='';for await(const chunk of process.stdin)input+=chunk;
const functions=new Map();
function build(v){switch(v[0]){
case 'undefined':return undefined;case 'null':return null;case 'boolean':return v[1];
case 'number':return Buffer.from(v[1],'hex').readDoubleBE();
case 'string':return String.fromCodePoint(...v[1]);
case 'symbol':return Symbol.for(String(v[1]));
case 'callable':if(!functions.has(v[1]))functions.set(v[1],()=>{});return functions.get(v[1]);
case 'bigint':return (v[1]?-1n:1n)*BigInt(v[2]);}}
const values=JSON.parse(input).map(build);
console.log(JSON.stringify({equal:values.map(a=>values.map(b=>a===b)),types:values.map(v=>typeof v)}));'''
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',oracle],input=json.dumps(values),text=True))
lines=['import Base','import ../packages/runtime/test/value.bend as T','import ../packages/runtime/src/value.bend as V','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/big-nat.bend as B']
for i,value in enumerate(values):
    lines += [f'def case{i}() -> IO(Unit):','  do IO<Unit>:',f'    T.checkType({bend(value)}, {json.dumps(expected["types"][i])})']
    for j,other in enumerate(values):
        lines.append(f'    T.check({bend(value)}, {bend(other)}, '+('True{}' if expected['equal'][i][j] else 'False{}')+f', "strict equality {i}/{j}")')
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(values))]+['    T.graph()',f'    IO.print("PASS {len(values)**2} strict-equality and {len(values)} typeof comparisons")']
source=BUILD/'runtime-value-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-runtime-values'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=60)
