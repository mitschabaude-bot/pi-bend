"""Original Pi string-literal repair and strict parse fallback in pure Bend."""
import itertools,json,random,subprocess
from pathlib import Path
from schema_literals import string,value
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
cases=['',' ','null','true','false','0','-0','1.25','[]','{}','{"x":1}','[1,]','{"x":}', 'unterminated"', '"unterminated', '"trailing\\', '\\outside','"\\u0041"','"\\u00"','"\\u0\"x"','"\\u\n"','"\\ud83d\\ude00"','"\ud800"','"😀"']
for c in [chr(i) for i in range(32)]+list('"\\/bfnrtuqa09')+['😀','\ud800']:
    cases.extend(['"before'+c+'after"','"before\\'+c+'after"','outside'+c+'"inside'+c+'"'])
for text in ['line\nnext','quote"text','path\\folder','null','😀','\udfff','tab\tdata']:
    cases.extend([json.dumps({'key':text}),'{"x":"'+text+'","y":2}','["'+text+'","after"]'])
rng=random.Random(7193);alphabet='ab{}[]:,"\\/unft0129\n\t\r\x00'
for _ in range(100):cases.append(''.join(rng.choice(alphabet) for _ in range(rng.randrange(1,50))))
# Prefixes exercise dangling escapes, partially written keys and delimiters.
for text in ['{"path":"C:\\new\\qfile","text":"line\nnext"}','["\\u1234", "\\u12", {"key":"value"}]']:
    cases.extend(text[:i] for i in range(len(text)+1))
expected=json.loads(subprocess.check_output(['node','tests/json_repair_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/test/json-repair.bend as Check','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(text,r) in enumerate(zip(cases,expected,strict=True)):
    parsed='Some{'+value(r['value'])+'}' if r['ok'] else 'None{}'
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([string(text),string(r['repaired']),parsed,f'"JSON repair {i}"'])+')']
groups=[]
for start in range(0,len(cases),30):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+30,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} JSON repair and parse comparisons")']
src=BUILD/'json-repair-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'json-repair-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
