"""Raw SSE through the native owned reader and public Responses processor.

Compare complete output snapshots and ordered source/emission/cleanup effects
with the actual pinned SDK plus actual pi processor. No HTTP/TLS is supplied.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
def event(kind,**fields):return dict(type='response.'+kind,**fields)
def frame(value):return 'data: '+json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n\n'
def terminal(**fields):return event('completed',response=dict(id='resp',status='completed',**fields))
def text(phase='commentary',content=None):return dict(type='message',id='msg',phase=phase,content=content or [])
base=[event('created',response={'id':'resp-start'}),event('output_item.added',output_index=2**32,item=text()),event('output_text.delta',output_index=2**32,delta='hello 🌍'),event('refusal.delta',output_index=2**32,delta='!'),event('output_item.done',output_index=2**32,item=text('final_answer',[{'type':'output_text','text':'hello 🌍!'}])),terminal(usage={'input_tokens':20,'output_tokens':4,'total_tokens':24,'input_tokens_details':{'cached_tokens':3,'cache_write_tokens':2},'output_tokens_details':{'reasoning_tokens':1}})]
reason=dict(type='reasoning',id='rs',summary=[])
function=dict(type='function_call',id='fc',call_id='call',name='tool',arguments='')
custom=dict(type='custom_tool_call',id='ct',call_id='custom',name='custom',input='')
tools=[event('output_item.added',output_index=0,item=reason),event('reasoning_summary_text.delta',output_index=0,delta='thought'),event('reasoning_summary_part.done',output_index=0),event('output_item.done',output_index=0,item={**reason,'summary':[{'type':'summary_text','text':'thought'}]}),event('output_item.added',output_index=9,item=function),event('function_call_arguments.delta',output_index=9,delta='{"x":'),event('function_call_arguments.done',output_index=9,arguments='{"x":1}'),event('output_item.done',output_index=9,item={**function,'arguments':'{"x":1}','namespace':'tools'}),event('output_item.added',output_index=1,item=custom),event('custom_tool_call_input.delta',output_index=1,delta='query'),event('custom_tool_call_input.done',output_index=1,input='query🌍'),event('output_item.done',output_index=1,item={**custom,'input':'query🌍','namespace':'tools'}),terminal(output=[{**reason,'encrypted_content':'opaque','unknown':'keep'}])]
cases=[]
def add(chunks,close='0',sink='0'):cases.append(dict(chunks=chunks,closeMode=close,sinkMode=sink))
for events in [base,tools,[terminal()],[event('incomplete',response={'status':'incomplete','incomplete_details':{'reason':'max_output_tokens'}})], [event('failed',response={'status':'failed','error':{'code':'bad','message':'broken'}})], [{'type':'error','code':'bad','message':'broken'}]]:
    frames=list(map(frame,events));joined=''.join(frames)
    for chunks in [frames,[joined],[list(joined.encode())],[None,'',*frames],list(joined)]:add(chunks)
    for close in ['0','1','2']:
        for sink in ['1','2']:add(frames,close,sink)
joined=''.join(map(frame,base))
for cut in [0,1,7,len(joined)//2,len(joined)-1,len(joined)]:add([joined[:cut],joined[cut:]])
for chunks in [[],['data: {\n\n'],['event: thread.run\ndata: {\n\n'],['data: {"error":"bad"}\n\n'],[{'error':True}],[{'abort':True}],['data: [DONE]\n\n'],['data: [DONE]\n\n',{'error':True}],['data: [DONE]\n\n',{'abort':True}],[joined,'data: [DONE]suffix\n\n','data: {\n\n'],[joined,{'error':True}],[joined,{'abort':True}],[frame({'type':'future','ignored':False}),joined],[frame(base[1]),'data: {\n\n'],[frame(terminal()).rstrip('\n')],[frame(base[1])]]:add(chunks)
expected=json.loads(subprocess.check_output(['node','tests/responses_pipeline_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
# Native protocol-validation failure has no JS coercion equivalent; verify its
# cleanup and error precedence separately, retaining the original output.
initial=next(want['output'] for case,want in zip(cases,expected,strict=True) if not case['chunks'])
for close in ['0','1','2']:
    add([frame(event('created',response={}))],close)
    expected.append(dict(output=initial,trace=['read','close','abort'],error='protocol:missing:/response/id'))

def codes(value):return ','.join(str(ord(c)) for c in value)
def chunk(value):
    if value is None:return 'n'
    if isinstance(value,dict):return 'a' if value.get('abort') else 'e'
    if isinstance(value,str):return 't'+codes(value)
    return 'b'+','.join(map(str,value))
arguments=['s'+'/'.join([case['closeMode'],case['sinkMode'],'|'.join(map(chunk,case['chunks'])),codes(json.dumps(want,ensure_ascii=True,separators=(',',':')))]) for case,want in zip(cases,expected,strict=True)]
(ROOT/'build').mkdir(exist_ok=True)
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'python3','scripts/run-rss-guarded.py','--stats','build/responses-pipeline-build-stats.json','--','sh','scripts/build-pure.sh','packages/ai/test/openai-responses-pipeline.bend','build/test-responses-pipeline'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(cases),2):
        actual=subprocess.check_output([str(ROOT/'build/test-responses-pipeline'),'--threads',threads,*arguments[start:start+2]],text=True,timeout=60).splitlines()
        assert len(actual)==len(cases[start:start+2]),(start,actual)
        for offset,result in enumerate(actual):assert result=='pass',(threads,start+offset,cases[start+offset],result)
    print(f'PASS raw SSE Responses pipeline: {len(cases)-3} SDK/pi comparisons and 3 native protocol failures on {threads} threads',flush=True)
