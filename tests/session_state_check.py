"""Replay actual pinned SessionManager mutations against immutable native state."""
import argparse,json,subprocess,tempfile
from pathlib import Path
import session_context_check as context
ROOT=Path(__file__).resolve().parents[1]
w=context.wire;o=context.opt;d=context.details

def usage(value):
 if value is None:return '-'
 return ','.join(str(value.get(k,0)) for k in ('input','output','cacheRead','cacheWrite','totalTokens'))+','+','.join(str(value['cost'].get(k,0)) for k in ('input','output','cacheRead','cacheWrite','total'))
def hook(value):return '-' if value is None else str(int(value))
def entry(e):
 b=':'.join([w(e['id']),o(e['parentId']),w(e['timestamp'])]);t=e['type']
 if t=='message':v='msg:'+context.message(e['message'])
 elif t=='thinking_level_change':v='thinking:'+w(e['thinkingLevel'])
 elif t=='model_change':v='model:'+w(e['provider'])+':'+w(e['modelId'])
 elif t=='compaction':
  sy=e.get('systemMessage');system='-' if sy is None else w(sy['content'])+':'+str(sy['timestamp'])
  v='compact:'+':'.join([w(e['summary']),w(e['firstKeptEntryId']),str(e['tokensBefore']),o(d(e.get('details'))),usage(e.get('usage')),hook(e.get('fromHook')),system])
 elif t=='branch_summary':v='summary:'+':'.join([w(e['fromId']),w(e['summary']),o(d(e.get('details'))),usage(e.get('usage')),hook(e.get('fromHook'))])
 elif t=='custom':v='custom:'+w(e['customType'])+':'+o(d(e.get('data')))
 elif t=='custom_message':v='visible:'+':'.join([w(e['customType']),w(e['content']),o(d(e.get('details'))),str(int(e['display']))])
 elif t=='label':v='label:'+w(e['targetId'])+':'+o(e.get('label'))
 elif t=='session_info':v='info:'+o(e.get('name'))
 else:raise AssertionError(t)
 return b+':'+v

def tree(nodes,depth=0):
 out=[]
 for n in nodes:
  out.append(':'.join([str(depth),w(n['entry']['id']),o(n.get('label')),o(n.get('labelTimestamp'))]));out.extend(tree(n['children'],depth+1))
 return out

def expected(step):
 a=step['after'];status='ok'
 if step.get('error'):status='error:missing:'+w(step['args'][0])
 children=dict(a['children']);queries='!'.join(w(k)+'='+';'.join(map(w,children[k]))+'='+';'.join(map(w,p)) for k,p in a['paths'])
 return '|'.join([status,o(a['leaf']),o(a['name']),';'.join(map(entry,a['entries'])),';'.join(w(e['id']) for e in a['branch']),';'.join(tree(a['tree'])),queries,context.expected(dict(kind='buildSessionContext',expected=a['context']))])

def operation(step):
 k=step['key'];args=step['args']
 if step.get('error'):
  if k=='appendLabelChange':
   e=dict(type='label',id='failed',timestamp='2025-01-01T00:00:00Z',parentId=None,targetId=args[0],label=args[1]);return '@'.join(['a',context.entry(e),'-','-','-'])
  if k=='branchWithSummary':
   e=dict(type='branch_summary',id='failed',timestamp='2025-01-01T00:00:00Z',parentId=args[0],fromId='',summary=args[1]);return '@'.join(['a',context.entry(e),'-','-','-'])
  if k=='createBranchedSession':return '@'.join(['f',w(args[0]),w('new'),'50,48,50,53,45,48,49,45,48,49,84,48,48,58,48,48,58,48,48,90',''])
 if k.startswith('append') or k=='branchWithSummary':
  e=dict(step['entry'])
  if k=='appendSessionInfo':e['name']=args[0] # exercise sanitization, not its output
  return '@'.join(['a',context.entry(e),usage(e.get('usage')),hook(e.get('fromHook')),o(d(e.get('details')))])
 if k=='branch':return 'b@'+w(args[0])
 if k=='resetLeaf':return 'r'
 if k=='createBranchedSession':
  h=step['header'];ids=[e['id'] for e in step['after']['entries'] if e['type']=='label'];return '@'.join(['f',w(args[0]),w(h['id']),w(h['timestamp']),'/'.join(map(w,ids))])
 raise AssertionError(k)

def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--reference',type=Path,default=ROOT.parent/'pi-mono/packages/coding-agent');a=p.parse_args();cmd=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 ref=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/session_state_reference.ts'),str(a.reference)],text=True));count=0
 for case in ref['cases']:
  h=case['header'];wire='|'.join([':'.join([w(h['id']),w(h['timestamp']),w(h['cwd'])]),*[operation(s) for s in case['steps']]])
  result=subprocess.run([*cmd,'--',wire],capture_output=True,text=True,timeout=90);want=[expected(s) for s in case['steps']];got=result.stdout.splitlines()
  assert result.returncode==0 and not result.stderr,(case['name'],result.stderr)
  if got!=want:
   for i,(g,v) in enumerate(zip(got,want)):
    if g!=v:
     Path('/tmp/session-state-mismatch.json').write_text(json.dumps(dict(case=case,index=i,got=g,want=v),indent=2));raise AssertionError((case['name'],i,g[:300],v[:300],'/tmp/session-state-mismatch.json'))
   raise AssertionError((case['name'],len(got),len(want)))
  count+=len(want)
 # Failed pure transitions leave the original session available unchanged.
 timestamp='2025-01-01T00:00:00Z';header=':'.join(map(w,['session',timestamp,'/work']))
 first=context.user('root',None,'hello')
 good='@'.join(['a',context.entry(first),'-','-','-'])
 invalid=[]
 for identifier,time,error in [('root',timestamp,'duplicate:'+w('root')),('',timestamp,'empty-id'),('bad','2025-02-30T00:00:00Z','timestamp:'+w('bad'))]:
  e=context.user(identifier,'root','not appended');e['timestamp']=time;invalid.append(('@'.join(['a',context.entry(e),'-','-','-']),error))
 label=dict(type='label',id='label',timestamp=timestamp,parentId='root',targetId='root',label='keep')
 labelled='@'.join(['a',context.entry(label),'-','-','-'])
 for ids,error in [('', 'label-id-count'),(w('root'),'duplicate:'+w('root')),(w('fresh')+'/'+w('extra'),'label-id-count')]:invalid.append(('@'.join(['f',w('root'),w('fork'),w(timestamp),ids]),error))
 for failed,error in invalid:
  result=subprocess.run([*cmd,'--','|'.join([header,good,labelled,failed])],capture_output=True,text=True,timeout=90)
  assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
  lines=result.stdout.splitlines();assert lines[-1].split('|',1)==['error:'+error,lines[-2].split('|',1)[1]],(error,lines)
 # A supplied recreated-label ID may equal an old removed label ID. Only
 # targets in the retained non-label path are eligible for label recreation.
 nested=dict(type='label',id='nested',timestamp=timestamp,parentId='label',targetId='label',label='label of label')
 nestedOp='@'.join(['a',context.entry(nested),'-','-','-'])
 fork='@'.join(['f',w('root'),w('fork'),w(timestamp),w('label')])
 result=subprocess.run([*cmd,'--','|'.join([header,good,labelled,nestedOp,fork])],capture_output=True,text=True,timeout=90)
 assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
 final=result.stdout.splitlines()[-1].split('|');assert final[0]=='ok' and len(final[3].split(';'))==2,final
 expectedTree=';'.join(['0:'+w('root')+':'+w('keep')+':'+w(timestamp),'1:'+w('label')+':-:-'])
 assert final[5]==expectedTree,final
 large=subprocess.check_output([*cmd,'--','wide','deep'],text=True,timeout=90).splitlines();assert large==['large-ok','large-ok'],large
 print(f'{len(ref["tests"])} original tests, {count} complete transition snapshots passed; {len(ref["skipped"])} named filesystem tests pending; 6 atomic rejection checks and 10,001-node wide/deep trees passed')
if __name__=='__main__':main()
