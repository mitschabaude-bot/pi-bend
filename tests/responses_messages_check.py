"""Actual full Responses transcript conversion versus the native pipeline."""
import copy,itertools,json,subprocess
from pathlib import Path
from schema_literals import string,seq,value
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
def text(s,**kw):return dict(type='text',text=s,**kw)
def user(content):return dict(role='user',content=content,timestamp=1)
def system(content='',**kw):return dict(role='system',content=content,timestamp=1,**kw)
def tool(name):return dict(name=name,description='Tool '+name,parameters={'type':'object','properties':{'input':{'type':'string'}},'required':['input']})
def call(id='call|ctc_1',args=None):return dict(type='toolCall',id=id,name='tool',arguments={'input':'a😀\ud800'} if args is None else args,namespace='ns')
def assistant(content,**kw):return dict(role='assistant',content=content,api='openai-responses',provider='openai',model='target',usage={'totalTokens':0},stopReason='stop',timestamp=1)|kw
def result(id='call|ctc_1',content=None):return dict(role='toolResult',toolCallId=id,toolName='tool',content=[text('done')] if content is None else content,isError=False,timestamp=1)
image=dict(type='image',data='AA==',mimeType='image/png')
cases=[]
def add(messages,options=None,reasoning=True,vision=True,developer=None,allowed=None):
    model=dict(id='target',api='openai-responses',provider='openai',reasoning=reasoning,input=['text','image'] if vision else ['text'],compat={} if developer is None else {'supportsDeveloperRole':developer})
    cases.append(dict(messages=copy.deepcopy(messages),options=options or {},model=model,allowed=['openai'] if allowed is None else allowed))
base=[system('initial',sections={'one':'section','two':None},toolsAdded=[tool('initial')]),user('hello'),system('updated',sections={'one':None,'new':'new section'},toolsAdded=[tool('later')]),assistant([text('answer')])]
for mid,include,reason,dev in itertools.product([None,False,True],[None,False,True],[False,True],[None,False,True]):
    add(base,{k:v for k,v in [('supportsMidConvoSystemMessages',mid),('includeSystemPrompt',include)] if v is not None},reasoning=reason,developer=dev)
for additional,search,mid,change in itertools.product([False,True],[False,True],[False,True],['add','redefine','remove','empty']):
    transcript=copy.deepcopy(base)
    if change=='redefine':transcript[2]['toolsAdded']=[tool('initial')]
    if change=='remove':transcript[2]['toolsRemoved']=[{'name':'initial'}]
    if change=='empty':transcript[2]['toolsAdded']=[]
    add(transcript,dict(supportsAdditionalTools=additional,supportsToolSearch=search,supportsMidConvoSystemMessages=mid))
for identity,allowed,grammar,vision in itertools.product(['same','model','provider','api'],[[],['openai']],[False,True],[False,True]):
    a=assistant([dict(type='thinking',thinking='think',thinkingSignature='{"type":"reasoning","id":"rs_1"}'),text('first',textSignature='signature'),call(),text('last')])
    if identity!='same':a[{'model':'model','provider':'provider','api':'api'}[identity]]='other'
    add([system(''),user([image,text('question')]),a,result(content=[image,text('ok')])],{'grammarToolInputProperties':{'tool':'input'}} if grammar else {},vision=vision,allowed=allowed)
for messages in [[],[user([])],[assistant([])],[assistant([dict(type='thinking',thinking='',thinkingSignature='')])],[system(''),user([]),assistant([]),system(''),assistant([text('a'),text('b')])],[user(''),system('later'),assistant([text('a')])],[assistant([call('call|fc_1')]),system('held'),user('next')],[assistant([call()],stopReason='error'),result()],[assistant([call()],stopReason='aborted')]]:
    for mid in [False,True]:add(messages,{'supportsMidConvoSystemMessages':mid})
for signature in ['{bad','null','{"type":"reasoning","id":"rs"}']:
    add([assistant([dict(type='thinking',thinking='t',thinkingSignature=signature)])])
for args in [{},{'input':42},{'input':''}]:add([assistant([call(args=args)]),result()],{'grammarToolInputProperties':{'tool':'input'}})
for search in [False,True]:
    bad=tool('bad');bad['constrainedSampling']={'type':'json_schema','strict':'require'};bad['parameters']={'type':'object','oneOf':[]}
    add([system('initial'),user('q'),system('',toolsAdded=[bad]),assistant([text('a')])],dict(supportsMidConvoSystemMessages=True,supportsAdditionalTools=not search,supportsToolSearch=search))
for args in [None, False, True, 0, -0.0, 3.5, '', 'text', [], [1, None, {'x': True}]]:
    item=call('call|fc_1')
    item['arguments']=args
    add([assistant([item]),result()])
expected=json.loads(subprocess.check_output(['node','tests/responses_messages_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def optional(v,enc=string):return 'None{}' if v is None else 'Some{'+enc(v)+'}'
def boolean(v):return 'True{}' if v else 'False{}'
def record(v,enc=value):return 'R.Record{'+seq('R.Property{'+string(k)+', '+enc(x)+'}' for k,x in v.items())+'}'
def blocks(bs):return seq('T.TextImageText{T.TextContent{'+string(b['text'])+', '+optional(b.get('textSignature'))+'}}' if b['type']=='text' else 'T.TextImageImage{T.ImageContent{'+string(b['data'])+', '+string(b['mimeType'])+'}}' for b in bs)
def ablock(b):
    if b['type']=='text':return 'T.AssistantText{T.TextContent{'+string(b['text'])+', '+optional(b.get('textSignature'))+'}}'
    if b['type']=='thinking':return 'T.AssistantThinking{T.ThinkingContent{'+string(b['thinking'])+', '+optional(b.get('thinkingSignature'))+', None{}}}'
    return 'T.AssistantToolCall{T.ToolCall{'+', '.join([string(b['id']),string(b['name']),value(b['arguments']),optional(b.get('thoughtSignature')),optional(b.get('namespace'))])+'}}'
def nativeTool(t):
    sampling='None{}' if 'constrainedSampling' not in t else 'Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Require{}}}}'
    return 'T.Tool{'+', '.join([string(t['name']),string(t['description']),value(t['parameters']),sampling])+'}'
def message(m):
    if m['role']=='user':return 'T.User{T.UserMessage{'+('T.UserText{'+string(m['content'])+'}' if isinstance(m['content'],str) else 'T.UserBlocks{'+blocks(m['content'])+'}')+', F.fromU32(1)}}'
    if m['role']=='assistant':return 'T.Assistant{Check.assistantJson('+', '.join([seq(map(ablock,m['content'])),string(m['api']),string(m['provider']),string(m['model']),'T.'+{'stop':'Stop','error':'Error','aborted':'Aborted'}[m['stopReason']]+'{}'])+')}'
    if m['role']=='toolResult':return 'T.ToolResult{T.ToolResultMessage{'+', '.join([string(m['toolCallId']),string(m['toolName']),blocks(m['content']),'None{}','None{}',boolean(m['isError']),'F.fromU32(1)'])+'}}'
    return 'T.System{T.SystemMessage{'+', '.join(['T.SystemText{'+string(m['content'])+'}',optional(m.get('sections'),lambda x:record(x,optional)),optional(m.get('toolsAdded'),lambda xs:seq(map(nativeTool,xs))),optional(m.get('toolsRemoved'),lambda xs:seq('T.ToolReference{'+string(x['name'])+'}' for x in xs)),'F.fromU32(1)'])+'}}'
def options(o):return 'Some{C.ConvertResponsesMessagesOptions{'+', '.join([optional(o.get('includeSystemPrompt'),boolean),optional(o.get('grammarToolInputProperties'),lambda x:record(x,string)),optional(o.get('supportsMidConvoSystemMessages'),boolean),optional(o.get('supportsAdditionalTools'),boolean),optional(o.get('supportsToolSearch'),boolean),'None{}'])+'}}'
lines=['import Base','import ../packages/ai/test/api/responses-messages.bend as Check','import ../packages/ai/src/api/openai-responses-shared.bend as C','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,r) in enumerate(zip(cases,expected,strict=True)):
    model='Check.model('+', '.join([boolean(c['model']['reasoning']),boolean('image' in c['model']['input']),optional(c['model']['compat'].get('supportsDeveloperRole'),boolean)])+')'
    result='Done{'+string(r['output'])+'}' if 'output' in r else 'Fail{'+string(r['error'])+'}'
    lines += [f'def case{i}() -> IO(Unit):','  Check.checkJson('+', '.join([model,seq(map(message,c['messages'])),seq(map(string,c['allowed'])),options(c['options']),result,f'"Responses transcript {i}"'])+')']
groups=[]
for start in range(0,len(cases),20):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+20,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} complete Responses transcript comparisons")']
src=BUILD/'responses-messages-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'responses-messages-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=180)
