"""Reasoning/signature replay against the actual pinned full transform."""
from upstream_pin import check_sibling
check_sibling()
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
whitespace=[*range(9,14),32,160,5760,*range(8192,8203),8232,8233,8239,8287,12288,65279]
texts=['','  ','thinking',' \nreasoning\t',*[chr(cp) for cp in whitespace+[0,133,6158,8203,8288]]]
identities=[('openai-responses','test-provider','test'),('anthropic-messages','test-provider','test'),('openai-responses','other','test'),('openai-responses','test-provider','other')]
cases=[]
for text,signature,redacted,identity in itertools.product(texts,[None,'','sig'],[None,False,True],identities):
    thinking={'type':'thinking','thinking':text,**({'thinkingSignature':signature} if signature is not None else {}),**({'redacted':redacted} if redacted is not None else {})}
    content=[{'type':'text','text':'answer','textSignature':'text-sig'},thinking,{'type':'toolCall','id':'call|id','name':'tool','arguments':'args','namespace':'ns',**({'thoughtSignature':signature} if signature is not None else {})}]
    cases.append(dict(content=content,api=identity[0],provider=identity[1],model=identity[2]))
expected=json.loads(subprocess.check_output(['node','tests/transform_replay_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def optional(value):return 'None{}' if value is None else 'Some{'+(str(value).capitalize()+'{}' if isinstance(value,bool) else string(value))+'}'
def content(values):
    output=[]
    for b in values:
        if b['type']=='text':output.append('Ai.AssistantText{Ai.TextContent{'+string(b['text'])+', '+optional(b.get('textSignature'))+'}}')
        elif b['type']=='thinking':output.append('Ai.AssistantThinking{Ai.ThinkingContent{'+string(b['thinking'])+', '+optional(b.get('thinkingSignature'))+', '+optional(b.get('redacted'))+'}}')
        else:output.append('Ai.AssistantToolCall{Ai.ToolCall{'+', '.join([string(b['id']),string(b['name']),string(b['arguments']),optional(b.get('thoughtSignature')),optional(b.get('namespace'))])+'}}')
    return ' <> '.join(output+['Nil{}'])
lines=['import Base','import ../packages/ai/test/api/transform-replay.bend as T','import ../packages/ai/src/types.bend as Ai']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  T.check('+', '.join([content(case['content']),content(result),string(case['api']),string(case['provider']),string(case['model']),string(f'replay {i}')])+')']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} typed assistant replay transformations")']
src=BUILD/'transform-replay-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'transform-replay-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
