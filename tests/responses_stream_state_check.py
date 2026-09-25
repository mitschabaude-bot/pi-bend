"""Compare interleaved Responses content and complete emission snapshots."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string,seq,floating
from responses_stream_literals import item,event_literal,record
ROOT=Path(__file__).resolve().parents[1]
cases=[]
def add(events,initial=(),properties=None):cases.append(dict(events=list(events),initial=list(initial),properties=properties or {}))
def event(kind,index,**fields):return dict(type='response.'+kind,output_index=index,**fields)
def added(index,output):return event('output_item.added',index,item=output)
def done(index,output):return event('output_item.done',index,item=output)
def text(id='m',phase=None,content='done'):return dict(type='message',id=id,content=[dict(type='output_text',text=content)],**({} if phase is None else {'phase':phase}))
def tool(custom=False,**kw):return dict(type='custom_tool_call' if custom else 'function_call',id='ctc_1' if custom else 'fc_1',call_id='call',name='tool',**({'input':''} if custom else {'arguments':''}),**kw)
def reasoning(id='rs'):return dict(type='reasoning',id=id,summary=[dict(type='summary_text',text='thought')])
items=[text(),tool(),tool(True),reasoning()]
# Missing slots ignore deltas; done-only events create and finalize slots.
for output in items:
    add([event('output_text.delta',7,delta='ignored'),done(7,output)])
    add([done(4,output),event('output_text.delta',4,delta='ignored'),done(4,output)])
# Every content kind can precede another; completion order need not be index order.
for first,second in itertools.product(items,repeat=2):
    add([added(42,first),added(3,second),event('output_text.delta',42,delta='a'),event('reasoning_text.delta',3,delta='b'),event('function_call_arguments.delta',42,delta='{}'),event('custom_tool_call_input.delta',3,delta='x'),done(42,first),done(3,second)])
# Reusing a live provider index creates a fresh assistant block. Mismatched
# completions preserve the slot, even when final_answer changes stopReason.
for first,second in itertools.product(items,repeat=2):
    add([added(0,first),added(0,second),done(0,first),done(0,second)])
    add([added(8,first),done(8,text('final','final_answer')),done(8,first)])
# Starting position includes pre-existing content and snapshots retain it.
for order in itertools.permutations([0,1,2]):
    starts=[added(9,text('a')),added(1,tool(True)),added(5,reasoning())]
    ends=[done(9,text('a',content='A')),done(1,{**tool(True),'input':'B','namespace':'late'}),done(5,reasoning())]
    add([*starts,*(ends[i] for i in order)],initial=[dict(type='text',text='existing',textSignature='old')],properties={'tool':'query'})
add([added(0,tool(True)),event('custom_tool_call_input.delta',0,delta='abc'),event('custom_tool_call_input.done',0,input='a'),added(1,text())])
add([added(3,tool()),event('function_call_arguments.done',3,arguments='null'),added(1,text()),done(3,{**tool(),'arguments':'null'})])
add([added(1,reasoning('rs')),added(2,reasoning('rs')),done(2,reasoning('rs')),done(1,reasoning('rs'))])
add([added(0,dict(type='web_search_call',id='ws')),done(0,dict(type='web_search_call',id='ws'))])
add([added(0,tool()),done(0,dict(type='web_search_call',id='ws')),event('function_call_arguments.delta',0,delta='{}'),done(0,tool())])
# Provider indices are keys, not allocation sizes or assistant positions.
for index in [2**32-1,2**32,2**53-1,1e100,-1,0.5]:
    add([added(index,text('sparse')),added(3,text('neighbor')),event('output_text.delta',index,delta='large'),done(3,text('neighbor')),done(index,text('sparse'))])
add([added(-0.0,text('zero')),event('output_text.delta',0,delta='same'),done(0,text('zero'))])
expected=json.loads(subprocess.check_output(['node','tests/responses_stream_state_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def native_event(e):
    index=floating(e['output_index'])
    if e['type']=='response.output_item.added':return 'D.Added{'+index+', '+item(e['item'])+'}'
    return 'D.Changed{'+index+', '+event_literal(e)+'}'
def initial_text(b):return 'T.AssistantText{T.TextContent{'+string(b['text'])+', Some{'+string(b['textSignature'])+'}}}'
lines=['import Base','import ../packages/ai/test/api/responses-stream-state.bend as Check','import ../packages/ai/src/api/openai-responses-stream.bend as D','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
# Expected snapshots reach the program as arguments: multi-kilobyte string
# literals overflow the compiler's literal expansion (BEND-016).
lines.insert(1,'import ../packages/runtime/test/utf8-runner.bend as Text')
for i,c in enumerate(cases):
    lines += [f'def case{i}(expected: String) -> IO(Unit):','  Check.check('+', '.join([seq(map(initial_text,c['initial'])),record(c['properties'],string),seq(map(native_event,c['events'])),'expected',string(f'Responses stream slots {i}')])+')']
lines += ['def run(index: U32, expected: String) -> IO(Unit):','  match index:']+[f'    case {i}: case{i}(expected)' for i in range(len(cases))]+['    case _: IO.die(Unit, 1, "unknown case")']
lines += ['def main() -> IO(Unit):','  do IO<Unit>:','    values : List<String> <- IO.args()','    dispatch(values)']
lines.insert(len(lines)-4,'def dispatch(values: List<String>) -> IO(Unit):\n  match values:\n    case index <> expected <> Nil{}: run(Text.decimal(index, 0), expected)\n    case _: IO.die(Unit, 1, "expected index expected")')
source=ROOT/'build/responses-stream-state-check.bend';source.write_text('\n'.join(lines)+'\n');out=ROOT/'build/responses-stream-state-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(source),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:
    for i,r in enumerate(expected):subprocess.run([str(out),'--threads',threads,str(i),r],cwd=ROOT,check=True,timeout=120)
    print(f'PASS {len(cases)} Responses multiplexed stream sequences on {threads} threads')
