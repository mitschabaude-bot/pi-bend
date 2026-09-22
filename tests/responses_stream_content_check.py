"""Content transitions compared with the actual pinned Responses processor.

These checks exercise one slot. Multiplexing, terminal events, usage/pricing,
transport and the public async driver remain separate integration requirements.
"""
import json, subprocess
from pathlib import Path
from schema_literals import string, seq, value
ROOT=Path(__file__).resolve().parents[1]
cases=[]
def add(item,events=(),properties=None):cases.append(dict(item=item,events=list(events),properties=properties or {}))
def event(kind,**fields):return dict(type='response.'+kind,**fields)
def done(item):return event('output_item.done',item=item)
def tool(kind='function_call',**fields):return dict(type=kind,id='fc_1' if kind=='function_call' else 'ctc_1',call_id='call',name='tool',**fields)
for initial in ['', '{"x":', '[1,', 'null', '3', '{"x":1}']:
    for final in ['', '{"x":2}', '[1,2]', 'null']:
        item=tool(arguments=initial)
        add(item,[event('function_call_arguments.delta',delta=''),event('function_call_arguments.done',arguments=final),done(tool(arguments=final,namespace='tools'))])
for text in ['{"city":"Rome"}', '[1,true,null]', 'false', '"hello"', '{"x":"a\\n"}', '{"x":']:
    for chunks in [[text],list(text)]:
        add(tool(arguments=''),[*(event('function_call_arguments.delta',delta=x) for x in chunks),done(tool(arguments=text))])
for final in ['{"a":1}', '{"a":', '[]', '']:
    add(tool(arguments='{"a":'),[event('function_call_arguments.done',arguments=final)])
for initial in ['', 'seed', 'a😀']:
    for prop in ['input','query','']:
        item=tool('custom_tool_call',input=initial,namespace='old')
        add(item,[event('custom_tool_call_input.delta',delta=' + b'),done(tool('custom_tool_call',input=initial+' + b',namespace='new'))],{'tool':prop})
        add(item,[event('custom_tool_call_input.done',input=initial),done(tool('custom_tool_call',input=initial))],{'tool':prop})
add(tool('custom_tool_call'),[done(tool('custom_tool_call'))])
add(tool('custom_tool_call',input='initial'),[event('custom_tool_call_input.delta',delta=''),done(tool('custom_tool_call'))])
for events in [
    [event('custom_tool_call_input.delta',delta='abc'),event('custom_tool_call_input.done',input='ab')],
    [event('custom_tool_call_input.done',input='abc'),event('custom_tool_call_input.delta',delta='d')],
    [event('custom_tool_call_input.done',input='abc'),event('custom_tool_call_input.done',input='ab')],
    [event('custom_tool_call_input.delta',delta='"\\\n'),done(tool('custom_tool_call',input='"\\\n'))],
]:add(tool('custom_tool_call',input=''),events)
for phase in [None,'commentary','final_answer']:
    item=dict(type='message',id='msg',content=[],**({} if phase is None else {'phase':phase}))
    for pieces in [[],[dict(type='output_text',text='final')],[dict(type='output_text',text='a'),dict(type='refusal',refusal='b')]]:
        final={**item,'content':pieces}
        add(item,[event('output_text.delta',delta='first'),event('refusal.delta',delta=' denied'),done(final)])
for summary,content in [([],[]),([{'text':'summary'}],[{'text':'content'}]),([],[{'text':'a'},{'text':'b'}]),([{'text':''}],[{'text':''}])]:
    item=dict(type='reasoning',id='rs',summary=[])
    final={**item,'summary':summary,'content':content,'encrypted_content':'opaque','extra':{'preserve':True}}
    add(item,[event('reasoning_summary_text.delta',delta='partial'),event('reasoning_summary_part.done'),event('reasoning_text.delta',delta='tail'),done(final)])
for item in [tool(arguments=''),tool('custom_tool_call',input=''),dict(type='message',id='msg',content=[]),dict(type='reasoning',id='rs',summary=[])]:
    add(item,[event('reasoning_text.delta',delta='r'),event('output_text.delta',delta='t'),event('function_call_arguments.delta',delta='{}'),event('custom_tool_call_input.delta',delta='c')])
    for wrong in [tool(arguments='{}'),tool('custom_tool_call',input='x'),dict(type='message',id='msg',content=[]),dict(type='reasoning',id='rs',summary=[])]:
        if item['type']!=wrong['type']:add(item,[done(wrong)])
add(dict(type='web_search_call',id='ws'))
expected=json.loads(subprocess.check_output(['node','tests/responses_stream_content_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
from responses_stream_literals import item, event_literal, record
lines=['import Base','import ../packages/ai/test/api/responses-stream-content.bend as Check','import ../packages/ai/src/api/openai-responses-stream.bend as D','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([item(c['item']),record(c['properties'],string),seq(map(event_literal,c['events'])),string(result),string(f'Responses content stream {i}')])+')']
groups=[]
for start in range(0,len(cases),20):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+20,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} Responses content-stream sequences")']
source=ROOT/'build/responses-stream-content-check.bend';source.write_text('\n'.join(lines)+'\n')
out=ROOT/'build/responses-stream-content-check'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
