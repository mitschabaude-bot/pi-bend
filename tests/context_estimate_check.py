"""Native context heuristic compared with pinned Pi, including usage selection."""
from upstream_pin import check_sibling
check_sibling()
import itertools, json, random, subprocess
from pathlib import Path
from schema_literals import string as literal_string, value, floating, seq
def string(s):
    return 'Check.repeat(4000n, Chr{120})' if s == 'x'*4000 else literal_string(s)
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'build'
def text(s): return {'type':'text','text':s}
def usage(n): return dict(input=n,output=0,cacheRead=0,cacheWrite=0,totalTokens=n,cost=dict(input=0,output=0,cacheRead=0,cacheWrite=0,total=0))
def assistant(t=100,n=2000,reason='stop',content=None): return dict(role='assistant',content=content or [text('kept')],timestamp=t,usage=usage(n),stopReason=reason)
def user(s,t=200):return dict(role='user',content=s,timestamp=t)
def system(s,**kwargs):return dict(role='system',content=s,timestamp=0,**kwargs)
image={'type':'image','data':'not counted','mimeType':'image/png'}
cases=[[],[system('system'),user('summary'),assistant(100,9500),user('x'*4000,300)],[user('summary'),assistant(100,9500),user('new prompt',300),assistant(400,2000),user('tail',500)]]
for content in ['', 'a', 'abcd', 'abcde', '😀', '😀😀x', '\ud800', 'e\u0301', [text('a'),text('b'),text('c'),text('d')], [image], [text('hello'),image,text('😀')]]:
    cases.append([user(content)])
    blocks=[text(content)] if isinstance(content,str) else content
    cases.append([dict(role='toolResult',content=blocks,timestamp=10)])
for reason,t,n in itertools.product(['stop','length','toolUse','error','aborted','deferred','pending'],[99,100,101],[0,1,2000]):
    cases.append([user('prefix',100),assistant(t,n,reason),user('tail',200)])
for fields in [dict(totalTokens=0,input=10,output=2,cacheRead=5,cacheWrite=3),dict(totalTokens=-1,input=100),dict(totalTokens=12,input=999,output=100)]:
    a=assistant();a['usage'].update(fields);cases.append([a,user('after')])
for sections in [None,{}, {'a':'','b':None,'c':'extra😀'}, {'a':'abcd','b':'abc'}]:
    for tools in [[],[dict(name='echo',description='desc',parameters={'type':'object','properties':{'a':{'type':'string'}}})],[dict(name='😀',description='',parameters={'const':[None,False,1.25,'x']},constrainedSampling=False)]]:
        cases.append([system([text('one'),text('two')],sections=sections,toolsAdded=tools,toolsRemoved=[{'name':'old'},{'name':'😀'}])])
for arguments in [None,True,123,1.25,[],{'emoji':'😀','quote':'"','nested':[1,2,3]}]:
    cases.append([assistant(n=0,content=[text('a'),{'type':'thinking','thinking':'hidden😀','redacted':True},{'type':'toolCall','id':'id','name':'fn','arguments':arguments}])])
rng=random.Random(8471)
pool=[user('summary',500),assistant(100,9500),assistant(600,2000),assistant(700,0),assistant(800,2000,'error'),assistant(900,2000,'aborted'),system('sys'),user('tail',1000)]
for _ in range(65):cases.append([rng.choice(pool) for _ in range(rng.randrange(1,8))])
results=json.loads(subprocess.check_output(['node','tests/context_estimate_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))

def maybe(v,fn):return 'None{}' if v is None else 'Some{'+fn(v)+'}'
def blocks(items):return seq('T.TextImageText{T.TextContent{'+string(b['text'])+', None{}}}' if b['type']=='text' else 'T.TextImageImage{T.ImageContent{"not counted", "image/png"}}' for b in items)
def content(c):return 'T.UserText{'+string(c)+'}' if isinstance(c,str) else 'T.UserBlocks{'+blocks(c)+'}'
def assistant_content(items):
    out=[]
    for b in items:
        if b['type']=='text':out.append('T.AssistantText{T.TextContent{'+string(b['text'])+', None{}}}')
        elif b['type']=='thinking':out.append('T.AssistantThinking{T.ThinkingContent{'+string(b['thinking'])+', None{}, Some{True{}}}}')
        else:out.append('T.AssistantToolCall{T.ToolCall{"id", '+string(b['name'])+', '+value(b['arguments'])+', None{}, None{}}}')
    return seq(out)
def tools(items):return seq('T.Tool{'+string(t['name'])+', '+string(t['description'])+', '+value(t['parameters'])+', '+('Some{T.SamplingDisabled{}}' if 'constrainedSampling' in t else 'None{}')+'}' for t in items)
def message(m):
    timestamp=floating(m['timestamp']);role=m['role']
    if role=='user':return 'T.User{T.UserMessage{'+content(m['content'])+', '+timestamp+'}}'
    if role=='toolResult':return 'T.ToolResult{T.ToolResultMessage{"id", "fn", '+blocks(m['content'])+', None{}, None{}, False{}, '+timestamp+'}}'
    if role=='system':
        c=m['content'];c='T.SystemText{'+string(c)+'}' if isinstance(c,str) else 'T.SystemBlocks{'+seq('T.TextContent{'+string(b['text'])+', None{}}' for b in c)+'}'
        sections=maybe(m.get('sections'),lambda x:'R.Record{'+seq('R.Property{'+string(k)+', '+maybe(v,string)+'}' for k,v in x.items())+'}')
        removed=maybe(m.get('toolsRemoved'),lambda x:seq('T.ToolReference{'+string(t['name'])+'}' for t in x))
        return 'T.System{T.SystemMessage{'+', '.join([c,sections,maybe(m.get('toolsAdded'),tools),removed,timestamp])+'}}'
    u=m['usage']; z='F.fromU32(0)';cost='T.UsageCost{'+', '.join([z]*5)+'}'
    usageval='T.Usage{'+', '.join([floating(u[k]) for k in ['input','output','cacheRead','cacheWrite']]+['None{}','None{}',floating(u['totalTokens']),cost])+'}'
    reason={'stop':'Stop','length':'Length','toolUse':'ToolUse','error':'Error','aborted':'Aborted','deferred':'Deferred','pending':'Pending'}[m['stopReason']]
    return 'T.Assistant{T.AssistantMessage{'+', '.join([assistant_content(m['content']), '"openai-responses"','"openai"','"test-model"']+['None{}']*4+[usageval,'T.'+reason+'{}']+['None{}']*4+[timestamp])+'}}'
lines=['import Base','import ../packages/ai/test/api/context-estimate.bend as Check','import ../packages/ai/src/utils/estimate.bend as E','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(messages,result) in enumerate(zip(cases,results,strict=True)):
    c=result['context'];expected='E.ContextUsageEstimate{'+', '.join([floating(c[k]) for k in ['tokens','usageTokens','trailingTokens']]+[maybe(c['lastUsageIndex'],lambda n:f'{n}n')])+'}'
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+seq(map(message,messages))+', '+expected+', '+seq(map(floating,result['individual']))+f', "context estimate {i}")']
groups=[]
for start in range(0,len(cases),30):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+30,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} context estimates and every constituent message estimate")']
src=BUILD/'context-estimate-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'context-estimate-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
