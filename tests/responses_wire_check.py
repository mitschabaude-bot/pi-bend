"""Source-derived JSON boundary vectors for the existing typed Responses model.

This tests decoding, not the complete provider. Existing processor differential
suites separately validate the semantics of the resulting native types.
"""
import itertools
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
cases = []
def add(mode, source, expected):
    cases.append((mode, source, json.dumps(expected, ensure_ascii=True, separators=(',', ':'))))
def bad(mode, source, expected):
    cases.append((mode, source, expected))
def project_item(value):
    kind = value.get('type')
    if kind == 'reasoning':
        return ['reasoning', value]
    if kind == 'message':
        return [kind, value['id'], value.get('phase'),
                [(p.get('text') if p['type']=='output_text' else p.get('refusal')) or '' for p in value.get('content') or []]]
    if kind == 'function_call':
        return [kind, value['id'], value['call_id'], value['name'], value.get('arguments') or '', value.get('namespace')]
    if kind == 'custom_tool_call':
        return [kind, value['id'], value['call_id'], value['name'], value.get('input'), value.get('namespace')]
    return ['other']
def project_response(value):
    usage=value.get('usage')
    if usage is not None:
        input_details=usage.get('input_tokens_details') or {}
        output_details=usage.get('output_tokens_details') or {}
        usage=[usage.get('input_tokens'),usage.get('output_tokens'),input_details.get('cached_tokens'),input_details.get('cache_write_tokens'),output_details.get('reasoning_tokens'),usage.get('total_tokens')]
    return [value.get('id'),value.get('status'),(value.get('incomplete_details') or {}).get('reason'),[project_item(x) for x in value.get('output') or []],usage,value.get('service_tier')]

items=[]
for phase,content in itertools.product([None,'commentary','final_answer'], [None,[],[{'type':'output_text','text':'hello🌍'}],[{'type':'output_text','text':'a','annotations':[]},{'type':'refusal','refusal':'b'}],[{'type':'future','refusal':'future refusal'},{'type':'refusal'}]]):
    items.append(dict(type='message',id='msg',phase=phase,content=content,ignored={'anything':True}))
items += [dict(type='message',id='msg'), {}, {'type':'web_search_call','id':'ws','unvalidated':[1,None]}]
for kind,key in [('function_call','arguments'),('custom_tool_call','input')]:
    for payload,namespace in itertools.product([None,'','{}','{"x":','query\n🌍'],[None,'','tools']):
        items.append(dict(type=kind,id='item',call_id='call',name='tool',namespace=namespace,**{key:payload}))
    items.append(dict(type=kind,id='item',call_id='call',name='tool'))
for payload in [{}, {'id':'rs','summary':[]}, {'id':'rs','summary':[{'type':'summary_text','text':'thought'}],'content':[{'text':'detail'}],'encrypted_content':'opaque','unknown':{'nested':[True,0,None,'🌍']}}]:
    items.append(dict(type='reasoning',**payload))
for item in items:
    add('i',item,project_item(item))
for status,usage in itertools.product([None,'completed','incomplete','failed','queued','future'],[None,{}, {'input_tokens':20,'output_tokens':4,'total_tokens':24}, {'input_tokens':-0.0,'output_tokens':-3,'input_tokens_details':{'cached_tokens':7,'cache_write_tokens':2},'output_tokens_details':{'reasoning_tokens':1}}, {'input_tokens':None,'input_tokens_details':None,'output_tokens_details':{} }]):
    value=dict(id='response',status=status,usage=usage,service_tier='priority',incomplete_details={'reason':'max_output_tokens'},output=items)
    add('r',value,project_response(value))
for value in [{},{'id':'','output':None,'usage':None,'incomplete_details':None},{'incomplete_details':{},'usage':{},'output':[]}]:
    add('r',value,project_response(value))
for code,message in itertools.product([None,'','bad'],[None,'','problem 🌍']):
    value={'code':code,'message':message,'ignored':True}
    add('e',value,[code,message])
add('e',{},[None,None])
for mode in ['i','r','e']:
    for value in [None,[],False,1,'text']:
        bad(mode,value,'type::object')
bad('i',{'type':'message'},'missing:/id')
bad('i',{'type':'message','id':None},'type:/id:string')
bad('i',{'type':'message','id':'m','phase':'future'},'value:/phase:commentary or final_answer')
bad('i',{'type':'message','id':'m','content':[{'type':'output_text','text':7}]},'type:/content/0/text:string')
bad('i',{'type':'message','id':'m','content':[None]},'type:/content/0:object')
bad('i',{'type':'message','id':'m','content':[{}]},'missing:/content/0/type')
bad('i',{'type':'function_call','id':'i'},'missing:/call_id')
bad('i',{'type':'custom_tool_call','id':'i','call_id':'c','name':'n','input':[]},'type:/input:string')
bad('i',{'type':3},'type:/type:string')
bad('r',{'output':[{}, {'type':'message','id':'m','content':[{},None]}]},'missing:/output/1/content/0/type')
bad('r',{'usage':{'input_tokens_details':{'cached_tokens':'7'}}},'type:/usage/input_tokens_details/cached_tokens:number')
bad('r',{'usage':{'output_tokens_details':{'reasoning_tokens':False}}},'type:/usage/output_tokens_details/reasoning_tokens:number')
bad('r',{'usage':{'input_tokens_details':[]}},'type:/usage/input_tokens_details:object')
bad('r',{'incomplete_details':{'reason':1}},'type:/incomplete_details/reason:string')
bad('e',{'code':9},'type:/code:string')

# Every discriminator consumed by the pinned processResponsesStream loop.
for index in [0,-0.0,42,2**32,2**53-1,1e100,-1,0.5]:
    for kind,field,tag in [
        ('reasoning_summary_text.delta','delta','thinking'),('reasoning_text.delta','delta','thinking'),
        ('output_text.delta','delta','text'),('refusal.delta','delta','text'),
        ('function_call_arguments.delta','delta','function_delta'),('function_call_arguments.done','arguments','function_done'),
        ('custom_tool_call_input.delta','delta','custom_delta'),('custom_tool_call_input.done','input','custom_done'),
    ]:
        for text in ['', 'piece🌍']:
            add('d',{'type':'response.'+kind,'output_index':index,field:text,'ignored':None},['changed',index,[tag,text]])
    add('d',{'type':'response.reasoning_summary_part.done','output_index':index,'part':None},['changed',index,['summary_done']])
    for item in items:
        add('d',{'type':'response.output_item.added','output_index':index,'item':item},['added',index,project_item(item)])
        add('d',{'type':'response.output_item.done','output_index':index,'item':item},['changed',index,['item_done',project_item(item)]])
for status in [None,'completed','incomplete','future']:
    response={'status':status,'output':items,'usage':{'input_tokens':7,'output_tokens':9},'incomplete_details':{'reason':'max_output_tokens'}}
    for kind in ['completed','incomplete']:
        add('d',{'type':'response.'+kind,'response':response},[kind,project_response(response)])
for response in [None,{}, {'status':'failed','error':{}}, {'status':'failed','error':{'code':'bad','message':'broken'}}, {'status':'incomplete','incomplete_details':{'reason':'limit'}}]:
    source={'type':'response.failed','response':response}
    data=response or {}
    error=data.get('error')
    add('d',source,['failed',data.get('status'),None if error is None else [error.get('code'),error.get('message')],(data.get('incomplete_details') or {}).get('reason')])
add('d',{'type':'response.failed'},['failed',None,None,None])
for code in [None,'','bad']:
    add('d',{'type':'error','code':code,'message':'problem'},['error',code,'problem'])
for mode in ['d','j']:
    add(mode,{'type':'response.created','response':{'id':'resp','unused':None}},['created','resp'])
    for source in [{},{'type':None},{'type':'future.event','output_index':{},'item':False}]:
        add(mode,source,['ignored'])
# Synthesized SSE envelopes have no top-level event type in pi's processor.
for source in [None,{'type':'response.created','response':{'id':'hidden'}}]:
    add('s',source,['ignored'])
for source,expected in [
    ({'type':'response.output_text.delta','delta':'x'},'missing:/output_index'),
    ({'type':'response.output_text.delta','output_index':'0','delta':'x'},'type:/output_index:number'),
    ({'type':'response.function_call_arguments.done','output_index':0},'missing:/arguments'),
    ({'type':'response.output_item.added','output_index':0,'item':{'type':'message'}},'missing:/item/id'),
    ({'type':'response.created','response':{}},'missing:/response/id'),
    ({'type':'response.completed'},'missing:/response'),
    ({'type':'response.failed','response':{'error':{'message':False}}},'type:/response/error/message:string'),
    ({'type':'error'},'missing:/message'),
    (None,'type::object'),
]: bad('d',source,expected)

def codes(value):
    return ','.join(str(ord(c)) for c in value)
arguments = ['s'+mode+'/'+codes(json.dumps(source,ensure_ascii=True))+'/'+codes(expected) for mode,source,expected in cases]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/ai/test/openai-responses-wire-runner.bend','build/test-openai-responses-wire'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(cases),8):
        actual=subprocess.check_output([str(ROOT/'build/test-openai-responses-wire'),'--threads',threads,*arguments[start:start+8]],text=True,timeout=30).splitlines()
        assert len(actual)==len(cases[start:start+8]),(start,actual)
        for offset,result in enumerate(actual):
            assert result=='pass',(threads,cases[start+offset],result)
    print(f'PASS Responses JSON boundary: {len(cases)} item/terminal/event/error vectors on {threads} native threads',flush=True)
