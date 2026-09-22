"""Compare the actual Responses assistant branch with typed native replay."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string,seq,value
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
def text(s,signature=None):return dict(type='text',text=s,**({} if signature is None else dict(textSignature=signature)))
def thinking(signature=None):return dict(type='thinking',thinking='private',**({} if signature is None else dict(thinkingSignature=signature)))
def call(id='call|fc_1',args=None,namespace=None):return dict(type='toolCall',id=id,name='tool',arguments={'input':'x'} if args is None else args,**({} if namespace is None else dict(namespace=namespace)))
cases=[]
def add(content,relation='same',grammar=None,index=3):cases.append(dict(content=content,relation=relation,grammar=grammar or {},index=index))
for signature in [None,'','legacy','x'*64,'x'*65,'😀'*32,'😀'*33,'\ud83d\ude00'*33,'{"v":1,"id":"","phase":"commentary"}','{"v":1,"id":"signed","phase":"final_answer"}','{"v":2,"id":"unknown"}','{bad']:
    for s in ['','text','a\ud800😀\udfff']:
        add([text(s,signature)])
for signature in [None,'','{}','null','false','[]','{"type":"reasoning","id":"rs_1","encrypted_content":"opaque","summary":[{"type":"summary_text","text":"summary"}],"extra":true}','{bad',' ','{"id":"rs_2"} tail']:
    add([thinking(signature),text('after')])
for relation,id,grammar,namespace in itertools.product(['same','different','foreign'],['call','call|','call|fc_1','call|ctc_1','call|rs_1|ignored','|fc_','||','call|fc'],[{}, {'tool':'input'}, {'other':'input'}],[None,'','namespace']):
    add([call(id,namespace=namespace)],relation,grammar)
for args in [{}, {'input':'a\ud800😀'}, {'input':'quote"\\\n'}, {'number':-0.0,'fraction':1.25,'nested':[True,None,{'x':'y'}]}]:
    add([call(args=args)])
for args,property in itertools.product([{}, {'input':None}, {'input':False}, {'input':[]}, {'input':3}, {'input':''}, {'input':'a\ud800😀'}, {'input':{'nested':'x'}}, {'input':'x','extra':[True,None,2]}],['input','other','']):
    add([text('before'),call(args=args),text('after')],grammar={'tool':property})
for index in [0,1,39,1000]:
    add([thinking(),text('a'),call(),thinking('{}'),text('b','explicit'),text('c'),text('d',''),thinking()],index=index)
add([])
add([thinking(),thinking('')])
add([thinking('{bad'),call(args={})],grammar={'tool':'input'})
add([call(args={}),thinking('{bad')],grammar={'tool':'input'})
# Streaming arguments are arbitrary JSON until tool validation. Replay must
# preserve these values, including null, rather than replace them with {}.
for args in [None, False, True, 0, -0.0, 3.5, '', 'text', [], [1, None, {'x': True}]]:
    for grammar in [{}, {'tool': 'input'}]:
        item=call()
        item['arguments']=args
        add([item],grammar=grammar)
expected=json.loads(subprocess.check_output(['node','tests/responses_assistant_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def optional(v):return 'None{}' if v is None else 'Some{'+string(v)+'}'
def record(v,encode=value):return 'R.Record{'+seq('R.Property{'+string(k)+', '+encode(x)+'}' for k,x in v.items())+'}'
def block(b):
    if b['type']=='text':return 'T.AssistantText{T.TextContent{'+string(b['text'])+', '+optional(b.get('textSignature'))+'}}'
    if b['type']=='thinking':return 'T.AssistantThinking{T.ThinkingContent{"private", '+optional(b.get('thinkingSignature'))+', None{}}}'
    return 'T.AssistantToolCall{T.ToolCall{'+', '.join([string(b['id']),string(b['name']),value(b['arguments']),'None{}',optional(b.get('namespace'))])+'}}'
lines=['import Base','import ../packages/ai/test/api/responses-assistant.bend as Check','import ../packages/ai/src/api/openai-responses-shared.bend as C','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,r) in enumerate(zip(cases,expected,strict=True)):
    # Null has no JS property access, so upstream throws a TypeError before
    # grammar validation. Native JSON reports the same rejection through the
    # existing typed missing-string error instead of emulating that exception.
    if c['grammar'] and any(b.get('type')=='toolCall' and b['arguments'] is None for b in c['content']):
        assert r == {'error': "Cannot read properties of null (reading 'input')"}, r
        r = {'error': 'Grammar tool call "tool" requires argument "input" to be a string.'}
    context='C.ReplayContext{'+', '.join(['True{}' if c['relation']=='same' else 'False{}','True{}' if c['relation']=='different' else 'False{}',str(c['index'])+'n',record(c['grammar'],string)])+'}'
    result='Done{'+string(r['output'])+'}' if 'output' in r else 'Fail{'+string(r['error'])+'}'
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([seq(map(block,c['content'])),context,result,f'"assistant replay {i}"'])+')']
groups=[]
for start in range(0,len(cases),30):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+30,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:','    Check.nativeArguments()']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} Responses assistant replay cases and native argument records")']
src=BUILD/'responses-assistant-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'responses-assistant-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
