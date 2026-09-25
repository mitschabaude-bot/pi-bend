"""Pinned schema grapheme policy and composed tool-validation length messages."""
from upstream_pin import check_sibling
check_sibling()
import json, random, subprocess
from pathlib import Path
from schema_literals import value,string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
dep=BUILD/'schema-reference/node_modules/typebox/package.json'
if not dep.exists(): subprocess.run(['npm','install','--prefix',str(BUILD/'schema-reference'),'--ignore-scripts','--no-audit','--no-fund','typebox@1.3.27'],check=True)
assert json.loads(dep.read_text())['version']=='1.3.27'
texts=['','a','abc','é','e\u0301','\u0301\u0302','a\u1ab0','a\u1dc0','a\ufe20','a\ufe0f','a\U000e0100','😀','👍🏽','👩\u200d💻','👩\u200d👩\u200d👧\u200d👦','🇩🇪','🇦🇧🇨','🇦🇧🇨🇩','a\u200d','\u200d','a\u200db\u200dc','\r\n','각','क़','x\0y','a\u0301b']
rng=random.Random(409)
alphabet=['a','b','\u0301','\u1ab0','\u1dc0','\ufe20','\ufe0f','\u200d','😀','🇦','🇧','🏽','ᄀ','\r','\n']
texts += [''.join(rng.choice(alphabet) for _ in range(rng.randrange(1,18))) for _ in range(180)]
lengths=json.loads(subprocess.check_output(['node','tests/schema_string_reference.mjs'],input=json.dumps(texts),text=True,cwd=ROOT))
cases=[]
for i,text in enumerate(texts):
    n=lengths[i]
    for lower,upper in [(n,n),(n+1,n-1 if n else 0)]:
        leaf={'type':'string','minLength':lower,'maxLength':upper}
        cases.append({'schema':{'type':'object','properties':{'value':leaf},'required':['value']},'value':{'value':text}})
for v in [None,False,True,0,12,[],{},['a']]:
    for typed in [False,True]:
        leaf={'minLength':1,'maxLength':1}
        if typed: leaf['type']='string'
        cases.append({'schema':{'type':'object','properties':{'value':leaf},'required':['value']},'value':{'value':v}})
for leaf,v in [({'type':'string','minLength':1e100},'a'),({'type':'string','maxLength':1e100},'a'),({'type':['number','string'],'minLength':2},'1'),({'anyOf':[{'type':'string','minLength':2},{'type':'null'}]},'x')]:
    cases.append({'schema':{'type':'object','properties':{'value':leaf},'required':['value']},'value':{'value':v}})
expected=json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/runtime/test/schema-string.bend as L','import ../packages/ai/test/plain-validation.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(text,n) in enumerate(zip(texts,lengths,strict=True)):
    lines += [f'def length{i}() -> IO(Unit):',f'  L.check({string(text)}, {n}, "schema grapheme {i}")']
for i,(c,e) in enumerate(zip(cases,expected,strict=True)):
    args=f'{value(c["value"])}, {value(c["schema"])}'
    lines += [f'def case{i}() -> IO(Unit):']
    if e['ok']:lines += [f'  T.check({args}, {value(e["value"])}, {value(c["value"])}, "string bound {i}")']
    else:lines += [f'  T.reject({args}, {value(c["value"])}, {string(e["message"])}, "string bound {i}")']
checks=[f'length{i}()' for i in range(len(texts))]+[f'case{i}()' for i in range(len(cases))]
groups=[]
for start in range(0,len(checks),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+['    '+c for c in checks[start:start+60]]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(texts)} schema grapheme counts and {len(cases)} composed length validations")']
source=BUILD/'schema-string-check.bend';source.write_text('\n'.join(lines)+'\n')
for src,name in [(source,'schema-string-check'),('packages/runtime/test/schema-string.bend','schema-string-native')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(src),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)
