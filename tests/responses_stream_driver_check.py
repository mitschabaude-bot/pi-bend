"""Actual-source reader/sink/tier ordering, failure snapshots and iterator cleanup."""
import argparse,json,subprocess
from pathlib import Path
from schema_literals import string,seq,floating
from responses_stream_literals import item,event_literal
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
batch=parser.add_mutually_exclusive_group()
batch.add_argument('--batch-size',type=int,default=8)
batch.add_argument('--single-batch',action='store_true',help='Compile all cases in one batch')
parser.add_argument('--generate-only',action='store_true',help='Generate oracle-backed fixtures without invoking the compiler')
args=parser.parse_args()
if args.batch_size < 1:parser.error('--batch-size must be positive')
cases=[]
def add(events,mode='NoHooks',requested=None,index=0):cases.append(dict(events=events,mode=mode,requested=requested,index=index))
def terminal(**fields):return dict(type='response.completed',response=fields)
for mode in ['NoHooks','ResolverOnly','PriceOnly','Both','ResolverFails','PricingFails']:
    for tier,requested in [(None,None),('','auto'),('priority','auto')]:
        add([terminal(id='final',status='completed',usage=dict(input_tokens=10,output_tokens=3,total_tokens=13),**({} if tier is None else dict(service_tier=tier)))],mode,requested)
custom=dict(type='custom_tool_call',id='ctc_1',call_id='call',name='tool',input='seed',namespace='old')
custom_events=[dict(type='response.output_item.added',output_index=4,item=custom),dict(type='response.output_item.done',output_index=4,item={**custom,'input':'seed + x','namespace':'new'}),terminal(status='completed')]
add(custom_events)
for mode,index in [('SinkFails',0),('SinkFails',1),('SinkFails',2),('CloseFails',1)]:add(custom_events,mode,index=index)
add([])
add([dict(type='response.unknown')])
add([terminal(status='completed'),dict(type='response.unknown')])
add([terminal(status='completed')],'ReadFails',index=0)
add([terminal(status='completed')],'ReadFails',index=1)
add([terminal(status='future')],'Both')
add([dict(type='response.incomplete',response=dict(status='incomplete',incomplete_details=dict(reason='content_filter')))])
add([dict(type='response.failed',response=dict(status='failed',error=dict(code='bad',message='provider failure')))])
add([dict(type='error',code=None,message='wire failure')])
expected=json.loads(subprocess.check_output(['node','tests/responses_stream_driver_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def optional(v,enc=string):return 'None{}' if v is None else 'Some{'+enc(v)+'}'
def usage(u):
    if u is None:return 'None{}'
    read=u.get('input_tokens_details') or {};out=u.get('output_tokens_details') or {}
    return 'Some{Terminal.ResponseUsage{'+', '.join(optional(v,floating) for v in [u.get('input_tokens'),u.get('output_tokens'),read.get('cached_tokens'),read.get('cache_write_tokens'),out.get('reasoning_tokens'),u.get('total_tokens')])+'}}'
def response(r):return 'Terminal.Response{'+', '.join([optional(r.get('id')),optional(r.get('status')),optional((r.get('incomplete_details') or {}).get('reason')),seq(item(x) for x in r.get('output',[])),usage(r.get('usage')),optional(r.get('service_tier'))])+'}'
def native_event(e):
    kind=e['type']
    if kind=='response.created':return 'D.ResponseCreated{'+string(e['response']['id'])+'}'
    if kind in ['response.completed','response.incomplete']:return 'D.'+('ResponseCompleted' if kind=='response.completed' else 'ResponseIncomplete')+'{'+response(e['response'])+'}'
    if kind=='response.failed':
        r=e['response'];err=r.get('error');native_error='None{}' if err is None else 'Some{Terminal.ProviderError{'+optional(err.get('code'))+', '+optional(err.get('message'))+'}}'
        return 'D.ResponseFailed{'+', '.join([optional(r.get('status')),native_error,optional((r.get('incomplete_details') or {}).get('reason'))])+'}'
    if kind=='error':return 'D.ResponseError{'+optional(e['code'])+', '+string(e['message'])+'}'
    if kind=='response.unknown':return 'D.IgnoredEvent{}'
    index=str(e['output_index'])+'n'
    native='S.Added{'+index+', '+item(e['item'])+'}' if kind=='response.output_item.added' else 'S.Changed{'+index+', '+event_literal(e)+'}'
    return 'D.ContentEvent{'+native+'}'
imports=['import Base','import ../packages/ai/test/api/responses-stream.bend as Check','import ../packages/ai/src/api/openai-responses-stream.bend as D','import ../packages/ai/src/api/openai-responses-terminal.bend as Terminal','import ../packages/ai/src/api/openai-responses-stream-state.bend as S','import ../packages/ai/src/api/openai-responses-stream-content.bend as C','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
batch_size=len(cases) if args.single_batch else args.batch_size
for start in range(0,len(cases),batch_size):
    stop=min(start+batch_size,len(cases));lines=list(imports)
    for i in range(start,stop):
        c,r=cases[i],expected[i];mode='Check.'+c['mode']+'{'+(str(c['index'])+'n' if c['mode'] in ['ReadFails','SinkFails','CloseFails'] else '')+'}'
        lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([seq(map(native_event,c['events'])),mode,optional(c['requested']),string(r),string(f'Responses async driver {i}')])+')']
    lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,stop)]+[f'    IO.print("PASS Responses async driver cases {start}–{stop-1}")']
    source=ROOT/f'build/responses-stream-driver-check-{start}.bend';source.write_text('\n'.join(lines)+'\n');out=source.with_suffix('')
    if args.generate_only:continue
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(out)],cwd=ROOT,check=True)
    for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
print(f'GENERATED {len(cases)} Responses async-driver fixtures; native tests not run' if args.generate_only else f'PASS {len(cases)} Responses async-driver sequences on one/four threads',flush=True)
