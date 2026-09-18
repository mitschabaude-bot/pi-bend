"""Pinned declaration reconciliation, including last-system intent and replay."""
import itertools
import json
import random
import subprocess
from pathlib import Path
from schema_literals import value, string

ROOT = Path(__file__).resolve().parents[1]
def tool(name='a', description='old'):
    return dict(name=name, description=description, parameters={'type':'object'})
def system(content='guidance', added=None, removed=None, **extra):
    result=dict(role='system',content=content,timestamp=12,**extra)
    if added is not None: result['toolsAdded']=added
    if removed is not None: result['toolsRemoved']=[dict(name=x) for x in removed]
    return result
def custom(text='user'):
    return dict(role='custom',content=text)

pools=[[],[tool()],[tool('a','new')],[tool('b')],[tool(),tool('b')],[tool('a','new'),tool('a','old')]]
previous=[[],[system(added=[tool()])],[system(added=[tool(),tool('b')]),system(removed=['a'])]]
pending=[[],[custom()],[system()],[custom('before'),system(added=[tool('invented')]),custom('after')],
         [system(added=[tool('b')]),custom(),system(removed=['a'])],
         [system(added=[],removed=[])],
         [system(content=[dict(type='text',text='block',textSignature='signed')],added=[tool('wrong')],sections={'a':'keep','b':None})]]
cases=[dict(previous=old,pending=new,tools=tools) for old,new,tools in itertools.product(previous,pending,pools)]
rng=random.Random(850103)
for _ in range(64):
    old=[system(added=[tool(rng.choice(['a','b','10']))],removed=[rng.choice(['a','b'])]) for _ in range(rng.randrange(4))]
    new=[rng.choice([custom(str(i)),system(added=rng.choice(pools),removed=[rng.choice(['a','b'])])]) for i in range(rng.randrange(5))]
    cases.append(dict(previous=old,pending=new,tools=rng.choice(pools)))
expected=json.loads(subprocess.check_output(['node','tests/tool_changes_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))

def items(values): return ''.join(v+' <> ' for v in values)+'Nil{}'
def maybe(value, show): return 'None{}' if value is None else 'Some{'+show(value)+'}'
def decl(t): return 'Ai.Tool{'+', '.join([string(t['name']),string(t['description']),value(t['parameters']),'None{}'])+'}'
def content(c):
    if isinstance(c,str): return 'Ai.SystemText{'+string(c)+'}'
    return 'Ai.SystemBlocks{'+items('Ai.TextContent{'+string(x['text'])+', '+maybe(x.get('textSignature'),string)+'}' for x in c)+'}'
def message(m):
    if m['role']=='custom': return 'T.CustomMessage{'+string(m['content'])+'}'
    sections=maybe(m.get('sections'),lambda fields:'R.Record{'+items('R.Property{'+string(k)+', '+maybe(v,string)+'}' for k,v in fields.items())+'}')
    return 'T.LlmMessage{Ai.System{Ai.SystemMessage{'+', '.join([content(m['content']),sections,maybe(m.get('toolsAdded'),lambda ts:items(decl(t) for t in ts)),maybe(m.get('toolsRemoved'),lambda rs:items('Ai.ToolReference{'+string(r['name'])+'}' for r in rs)),f'F.fromU32({m["timestamp"]})'])+'}}}'
lines=['import Base','import ../packages/agent/test/tool-changes.bend as Test','import ../packages/agent/src/types.bend as T','import ../packages/ai/src/types.bend as Ai','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F','def main() -> IO(Unit):','  do IO<Unit>:']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    args=[items(message(m) for m in case['previous']),items(message(m) for m in case['pending']),items(decl(t) for t in case['tools']),items(message(m) for m in result['value']),'True{}' if result['timestampNeeded'] else 'False{}',string(f'declaration reconciliation {i}')]
    lines.append('    Test.check('+', '.join(args)+')')
lines.append(f'    IO.print("PASS {len(cases)} upstream tool declaration reconciliation cases")')
source=ROOT/'build/tool-changes-check.bend';source.write_text('\n'.join(lines)+'\n');output=ROOT/'build/tool-changes-check'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=60)
