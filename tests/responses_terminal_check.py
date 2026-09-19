"""Actual-source terminal accounting, errors, status and reasoning backfill.

The test harness composes native prepare/finish without service-tier callbacks.
The production async driver and its callback ordering remain separate work.
"""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string,seq,floating as number
from responses_stream_literals import item,event_literal
ROOT=Path(__file__).resolve().parents[1]
cases=[]
base_cost=dict(input=2,output=8,cacheRead=.5,cacheWrite=3)
def add(events,cost=None):cases.append(dict(events=events,cost=cost or base_cost))
def terminal(**fields):return dict(type='response.completed',response=fields)
def done(index,output):return dict(type='response.output_item.done',output_index=index,item=output)
def tool():return dict(type='function_call',id='fc_1',call_id='call',name='tool',arguments='{}')
def reasoning(id='rs',**fields):return dict(type='reasoning',id=id,summary=[dict(type='summary_text',text='thought')],**fields)
for status,reason,has_tool in itertools.product([None,'','completed','incomplete','failed','cancelled','in_progress','queued','future'],[None,'','max_output_tokens','content_filter'],[False,True]):
    response={}
    if status is not None:response['status']=status
    if reason is not None:response['incomplete_details']={'reason':reason}
    add(([done(0,tool())] if has_tool else [])+[terminal(**response)])
for usage in [None,{},dict(input_tokens=100,output_tokens=20,total_tokens=120),dict(input_tokens=100,input_tokens_details=dict(cached_tokens=70,cache_write_tokens=20),output_tokens=20,output_tokens_details=dict(reasoning_tokens=8),total_tokens=120),dict(input_tokens=2,input_tokens_details=dict(cached_tokens=4,cache_write_tokens=5)),dict(input_tokens=-5,output_tokens=-2,input_tokens_details=dict(cached_tokens=-3,cache_write_tokens=1)),dict(input_tokens=1.5,output_tokens=2.25,total_tokens=10)]:
    for cost in [base_cost,{**base_cost,'tiers':[dict(input=4,output=16,cacheRead=1,cacheWrite=6,inputTokensAbove=20)]}]:
        add([terminal(status='completed',**({} if usage is None else {'usage':usage}))],cost)
for id in [None,'','final']:
    add([dict(type='response.created',response=dict(id='')),terminal(status='completed',**({} if id is None else {'id':id}))])
for old in [None,'','old']:
    for encrypted in [None,'','new']:
        saved=reasoning(extra={'keep':True},**({} if old is None else {'encrypted_content':old}))
        final=reasoning(**({} if encrypted is None else {'encrypted_content':encrypted}))
        add([done(8,saved),terminal(status='completed',output=[final]),terminal(status='completed',output=[reasoning(encrypted_content='later')])])
add([done(1,reasoning()),done(2,reasoning()),terminal(status='completed',output=[reasoning(encrypted_content='new')])])
add([terminal(status='completed',output=[reasoning(encrypted_content='unknown')])])
add([dict(type='response.output_item.added',output_index=0,item=reasoning()),terminal(status='completed',output=[reasoning(encrypted_content='unfinished')])])
add([terminal(status='completed'),done(0,tool())])
add([terminal(status='incomplete',incomplete_details={'reason':'content_filter'}),terminal(status='completed')])
for error,reason in itertools.product([None,{},dict(code='bad',message='failure'),dict(code='',message='')],[None,'','timeout']):
    response=dict(status='failed')
    if error is not None:response['error']=error
    if reason is not None:response['incomplete_details']={'reason':reason}
    add([dict(type='response.failed',response=response),terminal(status='completed')])
add([dict(type='error',code='bad',message='wire failure')])
add([dict(type='error',code=None,message='wire failure')])
add([])
add([done(0,tool())])
expected=json.loads(subprocess.check_output(['node','tests/responses_terminal_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def optional(v,enc=string):return 'None{}' if v is None else 'Some{'+enc(v)+'}'
def usage(u):
    if u is None:return 'None{}'
    read=u.get('input_tokens_details') or {};write=u.get('output_tokens_details') or {}
    return 'Some{Terminal.ResponseUsage{'+', '.join(optional(v,number) for v in [u.get('input_tokens'),u.get('output_tokens'),read.get('cached_tokens'),read.get('cache_write_tokens'),write.get('reasoning_tokens'),u.get('total_tokens')])+'}}'
def response(r):return 'Terminal.Response{'+', '.join([optional(r.get('id')),optional(r.get('status')),optional((r.get('incomplete_details') or {}).get('reason')),seq(item(x) for x in r.get('output',[])),usage(r.get('usage')),optional(r.get('service_tier'))])+'}'
def action(e):
    kind=e['type']
    if kind=='response.created':return 'Check.Created{'+string(e['response']['id'])+'}'
    if kind in ['response.completed','response.incomplete']:return 'Check.Completed{'+response(e['response'])+'}'
    if kind=='response.failed':
        r=e['response'];err=r.get('error');native_error='None{}' if err is None else 'Some{Terminal.ProviderError{'+optional(err.get('code'))+', '+optional(err.get('message'))+'}}'
        return 'Check.Failed{'+', '.join([optional(r.get('status')),native_error,optional((r.get('incomplete_details') or {}).get('reason'))])+'}'
    if kind=='error':return 'Check.WireError{'+optional(e['code'])+', '+string(e['message'])+'}'
    index=str(e['output_index'])+'n'
    native='S.Added{'+index+', '+item(e['item'])+'}' if kind=='response.output_item.added' else 'S.Changed{'+index+', '+event_literal(e)+'}'
    return 'Check.ContentEvent{'+native+'}'
def cost(c):
    tiers=c.get('tiers');encoded='None{}' if tiers is None else 'Some{'+seq('T.ModelCostTier{'+', '.join(number(x[k]) for k in ['input','output','cacheRead','cacheWrite','inputTokensAbove'])+'}' for x in tiers)+'}'
    return 'T.ModelCost{'+', '.join([*(number(c[k]) for k in ['input','output','cacheRead','cacheWrite']),encoded])+'}'
imports=['import Base','import ../packages/ai/test/api/responses-terminal.bend as Check','import ../packages/ai/src/api/openai-responses-terminal.bend as Terminal','import ../packages/ai/src/api/openai-responses-stream-state.bend as S','import ../packages/ai/src/api/openai-responses-stream-content.bend as C','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
# Keep the compiler's specialization working set bounded. Every case still
# runs natively on both thread counts; batching only changes build grouping.
for start in range(0,len(cases),16):
    stop=min(start+16,len(cases));lines=list(imports)
    for i in range(start,stop):
        c,r=cases[i],expected[i]
        lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([seq(map(action,c['events'])),cost(c['cost']),string(r),string(f'Responses terminal {i}')])+')']
    lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,stop)]
    lines += [f'    IO.print("PASS Responses terminal cases {start}–{stop-1}")']
    source=ROOT/f'build/responses-terminal-check-{start}.bend';source.write_text('\n'.join(lines)+'\n');out=source.with_suffix('')
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(out)],cwd=ROOT,check=True)
    for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
print(f'PASS {len(cases)} Responses terminal sequences on one/four threads',flush=True)
