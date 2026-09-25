"""Compare pure-Bend StringNumericLiteral conversion with Number(string)."""
import json
from pathlib import Path
import random
import subprocess
from schema_test_values import string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
values=['',' ','0','-0','+0','.0','-.0','1.','01','08','1e3','1.e-2','Infinity','+Infinity','-Infinity','NaN','inf','infinity','+','-','.','1e','1e+','1e-','0x','0b','0o','0x1','0Xff','0o77','0O10','0b11','0B11','-0x1','+0x1','0b2','0o8','0xg','0x1.2','0x1p2','1_000','1n','1 2','1\x002','1e3x','1..2','1e1e1','+ 1','--1','++1','1\ud800','\udfff1','١','１']
whitespace=[*range(9,14),32,160,5760,*range(8192,8203),8232,8233,8239,8287,12288,65279]
for cp in whitespace+[0,8,14,133,6158,8203,8288,65535]:
    values += [chr(cp),chr(cp)+'-0'+chr(cp),'1'+chr(cp)+'2']
for value in ['2.4703282292062327e-324','2.4703282292062328e-324','4.9406564584124654e-324','2.2250738585072011e-308','2.2250738585072014e-308','1.7976931348623157e308','1.7976931348623158e308','1.7976931348623159e308','9007199254740993','9007199254740995','1.00000000000000011102230246251565404236316680908203125','1.00000000000000033306690738754696212708950042724609375']:
    values += [value,'-'+value]
values += ['1e'+'9'*200,'1e-'+'9'*200,'-0e'+'9'*200,'0.'+'0'*450+'1e451','1'+'0'*450+'e-450','0.'+'0'*450+'1e450','1'+'0'*450+'e-451']
rng=random.Random(6400854)
for _ in range(160):
    digits=''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1,100)))
    pos=rng.randrange(len(digits)+1)
    values.append(rng.choice(['','+','-'])+digits[:pos]+'.'+digits[pos:]+rng.choice(['e','E'])+str(rng.randrange(-500,500)))
for radix,prefix in [(2,'0b'),(8,'0o'),(16,'0x')]:
    alphabet='0123456789abcdef'[:radix]
    for length in [1,13,53,54,64,256,1100]:
        values.append(prefix+''.join(rng.choice(alphabet) for _ in range(length)))
oracle="""let s='';for await(const x of process.stdin)s+=x;console.log(JSON.stringify(JSON.parse(s).map(t=>{const b=Buffer.alloc(8);b.writeDoubleBE(Number(t));return b.toString('hex')})));"""
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',oracle],input=json.dumps(values),text=True))
lines=['import Base','import ../packages/runtime/test/number-string.bend as T','import ../packages/runtime/src/f64.bend as F']
for i,(value,hexadecimal) in enumerate(zip(values,expected,strict=True)):
    raw=int(hexadecimal,16)
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({string(map(ord,value))}, F.fromBits({raw>>32}, {raw & 0xffffffff}), "numeric string {i}")']
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(values))]+[f'    IO.print("PASS {len(values)} Number(string) comparisons")']
source=BUILD/'number-string-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-number-string'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=180)
