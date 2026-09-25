"""Full base option construction compared with actual upstream helper."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import floating,string,value,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
cases=[]
for window,cap,base in itertools.product([-1,0,4096,4097,10000], [8000], [None,0,1,5000,20000]):
    for length in [0,5,100]:
        cases.append(dict(model=dict(contextWindow=window,maxTokens=cap),messages=[dict(role='user',content='x'*length,timestamp=0)],options=None if base is None else dict(maxTokens=base),key=None))
for modelSampling,optionSampling in itertools.product([None,{}, {'shared':1,'default':True}], [None,{}, {'shared':None,'custom':{'a':2}}]):
    for key in [None,'','explicit']:
        options=dict(apiKey='fallback',signal='signal',telemetryContext='telemetry',fetch='fetch',env={'KEY':'env'},headers={'removed':None,'empty':'','x':'header'},timeoutMs=10,maxRetries=0,maxRetryDelayMs=100,temperature=0,transport='websocket',cacheRetention='long',sessionId='session',websocketConnectTimeoutMs=20,metadata={'tag':True},reasoning='high',deferred=False,toolChoice='none',thinkingBudgets={'high':99})
        model=dict(contextWindow=20000,maxTokens=8000)
        if modelSampling is not None:model['samplingParams']=modelSampling
        if optionSampling is not None:options['samplingParams']=optionSampling
        cases.append(dict(model=model,messages=[],options=options,key=key))
# Optional empty strings must not vanish; enum variants survive projection.
for transport,cache in itertools.product(['sse','websocket','websocket-cached','auto'],['none','short','long']):
    cases.append(dict(model=dict(contextWindow=10000,maxTokens=7000),messages=[],options=dict(apiKey='',sessionId='',transport=transport,cacheRetention=cache),key=''))
results=json.loads(subprocess.check_output(['node','tests/base_options_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
fields=['signal','telemetryContext','apiKey','fetch','env','onPayload','onResponse','headers','timeoutMs','maxRetries','maxRetryDelayMs','temperature','samplingParams','maxTokens','transport','cacheRetention','sessionId','websocketConnectTimeoutMs','metadata']
strings={'signal','telemetryContext','apiKey','fetch','sessionId'};numbers={'timeoutMs','maxRetries','maxRetryDelayMs','temperature','maxTokens','websocketConnectTimeoutMs'}
def maybe(v,fn):return 'None{}' if v is None else 'Some{'+fn(v)+'}'
def record(v):return value(v)[len('V.ObjectValue{'):-1]
def env(v):return 'R.Record{'+seq('R.Property{'+string(k)+', '+string(s)+'}' for k,s in v.items())+'}'
def headers(v):return 'R.Record{'+seq('R.Property{'+string(k)+', '+('T.NullValue{}' if s is None else 'T.PresentValue{'+string(s)+'}')+'}' for k,s in v.items())+'}'
def field(k,v):
    if k in strings:return maybe(v,string)
    if k in numbers:return maybe(v,floating)
    if k in ['samplingParams','metadata']:return maybe(v,record)
    if k=='env':return maybe(v,env)
    if k=='headers':return maybe(v,headers)
    if k=='transport':return maybe(v,lambda s:'T.'+{'sse':'Sse','websocket':'WebSocket','websocket-cached':'WebSocketCached','auto':'AutoTransport'}[s]+'{}')
    if k=='cacheRetention':return maybe(v,lambda s:'T.'+{'none':'CacheNone','short':'CacheShort','long':'CacheLong'}[s]+'{}')
    assert v is None;return 'None{}'
def options(v,simple):
    vals=[field(k,v.get(k)) for k in fields]
    if simple: vals += ['Some{T.NoTool{}}','Some{T.High{}}','Some{T.DeferredBoolean{False{}}}','Some{T.ThinkingBudgets{None{}, None{}, None{}, Some{F.fromU32(99)}}}']
    return 'T.'+('SimpleStreamOptions' if simple else 'StreamOptions')+'{'+', '.join(vals)+'}'
lines=['import Base','import ../packages/ai/test/api/base-options.bend as Check','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,res) in enumerate(zip(cases,results,strict=True)):
    m=c['model'];model='Check.model('+floating(m['contextWindow'])+', '+floating(m['maxTokens'])+', '+maybe(m.get('samplingParams'),record)+')'
    messages=seq('T.User{T.UserMessage{T.UserText{'+string(m['content'])+'}, F.fromU32(0)}}' for m in c['messages'])
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([model,'T.TranscriptContext{'+messages+'}',maybe(c['options'],lambda v:options(v,True)),maybe(c['key'],string),options(res,False),f'"base options {i}"'])+')']
groups=[]
for start in range(0,len(cases),30):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+30,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} full base-option source comparisons")']
src=BUILD/'base-options-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'base-options-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
