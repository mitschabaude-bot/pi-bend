"""Strict immutable JSON decoding against JSON.parse acceptance and values."""
import json,random,subprocess,itertools
from pathlib import Path
from schema_literals import string,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
cases=['',' ','null','true','false','[]','{}','[null,true,false]','{"x":1,"x":2}','{"__proto__":{"x":1},"constructor":2}','{"2":"b","1":"a","x":null}','{"\\ud83d\\ude00":1,"😀":2}']
for value in ['0','-0','1','-1','1.25','1e2','1E+2','1e-2','9007199254740993','1.7976931348623157e308','1e309','-1e309','5e-324','2e-324','-1e-9999','1e9999']:
    cases += [value,'[ '+value+' ]','{"value":'+value+'}']
for bad in ['+0','01','-01','.1','1.','1e','1e+','--1','NaN','Infinity','0x10','0b10','00','truefalse','nul','undefined','[1,]','{"x":1,}','{"x" 1}','{x:1}','[,1]','[1 2]','{}[]','true true','[','{','[1','{"x":','{"x"','/*x*/0','0 //comment']:
    cases += [bad,'['+bad+']']
for whitespace in [' ','\t','\r','\n',' \n\t\r','\ufeff','\u00a0','\v','\f','\u2028']:
    cases += [whitespace+'0'+whitespace,'['+whitespace+'0'+whitespace+']']
for char in ['"','\\','/','\b','\f','\n','\r','\t','\0','\x1f','é','😀','\ud800','\udc00','\ud83d\ude00']:
    cases.append(json.dumps(char));cases.append('"'+char+'"')
for escape in ['\\u0000','\\u0041','\\ud800','\\udc00','\\ud83d\\ude00','\\uD83D\\uDE00','\\u12','\\uZZZZ','\\x20','\\v','\\0','\\','\\/','\\q']:
    cases.append('"'+escape+'"')
rng=random.Random(830)
def tree(depth):
    scalar=rng.choice([None,False,True,0,-1,1.25,'hello😀','line\nbreak'])
    if depth==0:return scalar
    choice=rng.randrange(3)
    if choice==0:return scalar
    if choice==1:return [tree(depth-1) for _ in range(rng.randrange(4))]
    return {f'field{i}':tree(depth-1) for i in range(rng.randrange(4))}
for _ in range(80):
    text=json.dumps(tree(3),ensure_ascii=True,separators=(',',':'));cases += [text,text[:-1],text+'x']
for sign,integer,fraction,exponent in itertools.product(['','-'],['0','1','12'],['','.0','.125'],['','e0','E-10','e+3']):cases.append(sign+integer+fraction+exponent)
# Native strings contain Unicode scalars; raw isolated UTF-16 units cannot enter this API.
cases=[text for text in cases if not any(0xD800 <= ord(c) <= 0xDFFF for c in text)]
cases += ['"\\ud800x"','"\\ud800\\u0041"','"\\ud800\\ud800"','"\\udc00\\ud800"','"\\ud800\\udc00"','"\\udbff\\udfff"']
expected=json.loads(subprocess.check_output(['node','tests/json_parse_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
def scalar_text(text):
    return not any(0xD800 <= ord(c) <= 0xDFFF for c in text)
def scalar_value(node):
    if 'text' in node:return scalar_text(node['text'])
    if 'array' in node:return all(map(scalar_value,node['array']))
    if 'object' in node:return all(scalar_text(k) and scalar_value(v) for k,v in node['object'])
    return True
# Approved strict native adaptation: JSON.parse accepts lone surrogate units;
# Bend reports a typed InvalidEscape instead of constructing an invalid Char.
expected=[result if not result['ok'] or scalar_value(result['value']) else {'ok':False} for result in expected]
def value(node):
    if 'null' in node:return 'V.Null{}'
    if 'number' in node:return 'V.Number{F.fromBits('+', '.join(map(str,node['number']))+')}'
    if 'text' in node:return 'V.Text{'+string(node['text'])+'}'
    if 'boolean' in node:return 'V.Boolean{'+('True{}' if node['boolean'] else 'False{}')+'}'
    if 'array' in node:return 'V.ArrayValue{'+seq(value(v) for v in node['array'])+'}'
    return 'V.ObjectValue{R.Record{'+seq('R.Property{'+string(k)+', '+value(v)+'}' for k,v in node['object'])+'}}'
lines=['import Base','import ../packages/runtime/test/json-parse.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(text,result) in enumerate(zip(cases,expected,strict=True)):
    want='Some{'+value(result['value'])+'}' if result['ok'] else 'None{}'
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({string(text)}, {want}, "JSON parse {i}")']
groups=[]
for start in range(0,len(cases),35):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+35,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+['    T.deep()',f'    IO.print("PASS {len(cases)} strict JSON acceptance/value comparisons and 2000-level nesting")']
src=BUILD/'json-parse-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'json-parse-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
