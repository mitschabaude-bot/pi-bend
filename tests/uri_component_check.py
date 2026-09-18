"""Pure Bend percent-decoding comparisons against decodeURIComponent."""
import json
from pathlib import Path
import random
import subprocess
from urllib.parse import quote
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
values=['','plain','a+b','%00','%2F','%7e','%25','%','%1','%xz','%80','%C0%80','%C1%BF',
        '%E0%80%80','%ED%A0%80','%ED%BF%BF','%F0%80%80%80','%F4%90%80%80','%F5%80%80%80',
        '%FF','%FE','%E2','%E2%82','%E2%28%A1','%E2%82x','%C2x','%C2%C2','%F0%9F%98%80',
        '%F4%8F%BF%BF','%ED%9F%BF','%E0%A0%80','%C2%80','😀','a%20b%2Bc']
rng=random.Random(714)
for _ in range(180):
    codes=[rng.choice([rng.randrange(128),rng.randrange(128,2048),rng.randrange(2048,55296),rng.randrange(57344,1114112)]) for _ in range(rng.randrange(1,9))]
    text=''.join(map(chr,codes))
    values.append(quote(text,safe='/~+'))
    values.append(text)
js="let s='';for await(const c of process.stdin)s+=c;process.stdout.write(JSON.stringify(JSON.parse(s).map(x=>{try{return decodeURIComponent(x)}catch{return null}})))"
expected=json.loads(subprocess.check_output(['node','--input-type=module','-e',js],input=json.dumps(values),text=True))
lines=['import Base','import ../packages/runtime/src/uri-component.bend as U','import ../packages/runtime/test/json-pointer.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for v,e in zip(values,expected,strict=True):
    result='None{}' if e is None else 'Some{'+string(e)+'}'
    lines.append(f'    T.decoded(U.decode({string(v)}), {result})')
lines.append(f'    IO.print("PASS {len(values)} native URI component decoding comparisons")')
source=BUILD/'uri-component-check.bend'; source.write_text('\n'.join(lines)+'\n')
for source,name in [(source,'uri-component-check'),('packages/runtime/test/json-pointer.bend','json-pointer-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
