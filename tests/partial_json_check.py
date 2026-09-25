"""Pinned partial-json default mode and Pi's full streaming JSON composition."""
from upstream_pin import check_sibling
check_sibling()
import itertools,json,random,subprocess
from pathlib import Path
from schema_literals import string,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
cases=[None,'',' ','\t\n','\ufeff','\u00a0','{}','[]','null','null extra','true junk','"ok" tail','0 trailing','-','-0','NaN','Infinity','-Infinity']
for text in ['null','true','false','NaN','Infinity','-Infinity','1.25e+3','-2E-4','"a\\n\\u0041😀"','"bad\\qescape"','{"name":"alpha","count":12,"enabled":true,"items":[1,2,null]}','{"path":"C:\\file\\q", "text":"line\nbreak"}','[[1,2],[3,{"x":"partial string"}]]','{"a":1e+,"later":"e"}','[1e+,"e"]','{"a":"unclosed\\u12']:
    cases.extend(text[:i] for i in range(len(text)+1))
for fragment in ['',' ','-', '1e','1e+','1E+','01','.1','Na','Inf','-Inf','tru','nul','"abc','"abc\\','"\\u12','"bad\\q','"x\n','"a" "b"','truefalse','[ ]','{ }','[1,]','{"a":1,}','{"a"x1}','{"a" 1}','undefined']:
    for wrapper in [lambda x:x,lambda x:'['+x,lambda x:'{"value":'+x,lambda x:'[1,'+x+']',lambda x:'{"first":1,"second":'+x+'}']:
        cases.append(wrapper(fragment))
for control in ['\x00','\x01','\b','\t','\n','\f','\r','\x1f','\ud800','\udfff','😀']:
    cases.extend(['"a'+control+'b','{"x":"a'+control+'b','["a\\'+control+'b'])
for whitespace in [' ','\t','\n','\r','\u00a0','\ufeff','\v']:
    cases += [whitespace+'tru'+whitespace,'[1,'+whitespace+'2', '{'+whitespace+'"x":1']
rng=random.Random(2461);alphabet='abefntruIN{}[]:,"\\012-+. \n'
for _ in range(100):cases.append(''.join(rng.choice(alphabet) for _ in range(rng.randrange(1,45))))
# Ordering/prototype emulation is excluded; ordinary duplicate dictionary keys
# retain their last value while the representation stays immutable.
cases += ['{"a":1,"a":2','{"constructor":3}','{"2":"b","1":"a"','{"x":[NaN,Infinity,-Infinity,-0]']
expected=json.loads(subprocess.check_output(['node','tests/partial_json_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def value(n):
    if 'null' in n:return 'V.Null{}'
    if 'number' in n:return 'V.Number{F.fromBits('+', '.join(map(str,n['number']))+')}'
    if 'text' in n:return 'V.Text{'+string(n['text'])+'}'
    if 'boolean' in n:return 'V.Boolean{'+('True{}' if n['boolean'] else 'False{}')+'}'
    if 'array' in n:return 'V.ArrayValue{'+seq(value(x) for x in n['array'])+'}'
    return 'V.ObjectValue{R.Record{'+seq('R.Property{'+string(k)+', '+value(x)+'}' for k,x in n['object'])+'}}'
lines=['import Base','import ../packages/runtime/test/partial-json.bend as Check','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(text,r) in enumerate(zip(cases,expected,strict=True)):
    input='None{}' if text is None else 'Some{'+string(text)+'}'
    partial='Some{'+value(r['raw']['value'])+'}' if r['raw']['ok'] else 'None{}'
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([input,partial,value(r['streaming']),f'"case {i}"'])+')']
groups=[]
for start in range(0,len(cases),25):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+25,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+['    Check.deep()','    Check.literalKeys()',f'    IO.print("PASS {len(cases)} partial/streaming JSON comparisons and 2000 unclosed containers")']
src=BUILD/'partial-json-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'partial-json-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=180)
