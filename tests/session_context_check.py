"""Pinned session context assertions and typed invalid-tree boundaries."""
import argparse,datetime,json,random,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
STAMP='2025-01-01T00:00:00Z'
def wire(value):return ','.join(str(ord(c)) for c in value)
def opt(value):return '-' if value is None else wire(value)
def details(value):return None if value is None else json.dumps(value,separators=(',',':'),ensure_ascii=False)
def entry(e):
 result=[wire(e['id']),opt(e['parentId']),wire(e['timestamp'])];k=e['type']
 if k=='message':
  m=e['message'];role=m['role']
  if role=='user':fields=['u',wire(m['content'])]
  elif role=='system':fields=['s',wire(m['content'])]
  elif role=='assistant':fields=['a',wire(''.join(b.get('text','') for b in m['content'])),wire(m['provider']),wire(m['model'])]
  else:raise AssertionError(role)
 elif k=='thinking_level_change':fields=['t',wire(e['thinkingLevel'])]
 elif k=='model_change':fields=['m',wire(e['provider']),wire(e['modelId'])]
 elif k=='compaction':fields=['c',wire(e['summary']),wire(e['firstKeptEntryId']),str(e['tokensBefore']),opt(e.get('systemMessage',{}).get('content'))]
 elif k=='branch_summary':fields=['b',wire(e['summary']),wire(e['fromId'])]
 elif k=='custom':fields=['x',wire(e['customType']),opt(details(e.get('data')))]
 elif k=='custom_message':fields=['v',wire(e['customType']),wire(e['content']),str(int(e['display'])),opt(details(e.get('details')))]
 elif k=='label':fields=['l',wire(e['targetId']),opt(e.get('label'))]
 elif k=='session_info':fields=['i',opt(e.get('name'))]
 else:raise AssertionError(k)
 return ':'.join(result+fields)
def message(m):
 role=m['role']
 if role=='user':return 'user:'+wire(m['content'])
 if role=='system':return 'system:'+wire(m['content'])
 if role=='assistant':return 'assistant:'+wire(''.join(b.get('text','') for b in m['content']))+':'+wire(m['provider'])+':'+wire(m['model'])
 if role=='compactionSummary':return f"compaction:{wire(m['summary'])}:{m['tokensBefore']}:{m['timestamp']}"
 if role=='branchSummary':return f"branch:{wire(m['summary'])}:{opt(m.get('fromId'))}:{m['timestamp']}"
 if role=='custom':return f"custom:{wire(m['customType'])}:{wire(m['content'])}:{int(m['display'])}:{opt(details(m.get('details')))}:{m['timestamp']}"
 raise AssertionError(role)
def expected(c):
 value=c['expected']
 if c['kind']=='buildContextEntries':return 'entries|'+';'.join(wire(e['id']) for e in value)
 model=value['model'];chosen='-' if model is None else wire(model['provider'])+':'+wire(model['modelId'])
 return 'context|'+wire(value['thinkingLevel'])+'|'+chosen+'|'+';'.join(map(message,value['messages']))
def command(c,operation=None):
 args=c['args'];leaf='latest' if len(args)==1 else 'root' if args[1] is None else wire(args[1])
 return '|'.join([operation or ('entries' if c['kind']=='buildContextEntries' else 'context'),leaf,';'.join(map(entry,args[0]))])
def base(i,parent,kind,**fields):return dict(id=str(i),parentId=parent,type=kind,timestamp=STAMP,**fields)
def user(i,parent,text):return base(i,parent,'message',message=dict(role='user',content=text,timestamp=1))
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--reference',type=Path,default=ROOT.parent/'pi-mono/packages/coding-agent');a=p.parse_args()
 cmd=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 cases=[];rng=random.Random(606)
 for _ in range(150):
  entries=[]
  for i in range(rng.randrange(1,35)):
   parent=None if not entries or rng.randrange(12)==0 else rng.choice(entries)['id'];kind=rng.randrange(9)
   if kind<2:e=user(i,parent,'user '+str(i))
   elif kind==2:e=base(i,parent,'thinking_level_change',thinkingLevel=rng.choice(['off','high','low']))
   elif kind==3:e=base(i,parent,'model_change',provider='provider',modelId='model '+str(i))
   elif kind==4:e=base(i,parent,'compaction',summary='summary '+str(i),firstKeptEntryId=str(rng.randrange(i+1)),tokensBefore=1000,**({'systemMessage':dict(role='system',content='snapshot '+str(i),timestamp=1)} if rng.randrange(2) else {}))
   elif kind==5:e=base(i,parent,'branch_summary',summary=rng.choice(['','branch']),fromId='other')
   elif kind==6:e=base(i,parent,'custom_message',customType='custom',content='content '+str(i),display=bool(rng.randrange(2)),details={'value':i})
   elif kind==7:e=base(i,parent,'message',message=dict(role='system',content='system '+str(i),timestamp=1))
   else:e=base(i,parent,'custom',customType='state',data={'value':i})
   entries.append(e)
  args=[entries] if rng.randrange(3)==0 else [entries,rng.choice([None,'missing','',rng.choice(entries)['id']])]
  cases.extend(dict(kind=kind,args=args) for kind in ['buildContextEntries','buildSessionContext'])
 focused=[user('1',None,'before'),base('2','1','thinking_level_change',thinkingLevel='high'),base('3','2','model_change',provider='openai',modelId='chosen'),base('4','3','message',message=dict(role='system',content='old system',timestamp=1)),user('5','4','kept'),base('6','5','compaction',summary='summary',firstKeptEntryId='4',tokensBefore=123,systemMessage=dict(role='system',content='new system',timestamp=1)),base('7','6','label',targetId='5',label='bookmark'),base('8','7','session_info',name='name'),base('9','8','custom_message',customType='hidden',content='still context',display=False,details={'value':'$1'})]
 for leaf in [None,'3','6','9','missing','']:
  cases.extend(dict(kind=k,args=[focused,leaf]) for k in ['buildContextEntries','buildSessionContext'])
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'cases.json';path.write_text(json.dumps(cases))
  reference=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/session_context_reference.ts'),str(a.reference),str(path)],text=True))
 for start in range(0,len(reference),20):
  batch=reference[start:start+20];r=subprocess.run([*cmd,'--',*[command(c) for c in batch]],capture_output=True,text=True,timeout=60)
  want=[expected(c) for c in batch]
  assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
  assert r.stdout.splitlines()==want,[(c,g,w) for c,g,w in zip(batch,r.stdout.splitlines(),want) if g!=w][:2]
 # Check raw parent paths separately, before compaction removes entries.
 for c in cases[::2]:
  args=c['args'];entries=args[0];index={e['id']:e for e in entries};leaf=args[1] if len(args)>1 else 'missing'
  current=None if leaf is None else index.get(leaf) or (entries[-1] if entries else None);path=[]
  while current:path.append(current['id']);current=index.get(current['parentId'])
  want='entries|'+';'.join(wire(i) for i in path[::-1])
  got=subprocess.check_output([*cmd,'--',command(c,'path')],text=True).strip();assert got==want,(c,got,want)
 invalid=[([user('x',None,'a'),user('x',None,'b')],'duplicate:'+wire('x')),([user('',None,'a')],'empty-id'),([user('x','x','a')],'cycle:'+wire('x')),([user('a','b','a'),user('b','a','b')],'cycle:'+wire('b'))]
 for entries,want in invalid:
  c=dict(kind='buildSessionContext',args=[entries]);got=subprocess.check_output([*cmd,'--',command(c)],text=True).strip();assert got=='error|'+want,(got,want)
 invalidTime=base('bad',None,'custom_message',customType='custom',content='text',display=True);invalidTime['timestamp']='2025-02-30T00:00:00Z'
 got=subprocess.check_output([*cmd,'--',command(dict(kind='buildSessionContext',args=[[invalidTime]]))],text=True).strip();assert got=='error|timestamp:'+wire('bad'),got
 assert subprocess.check_output([*cmd,'--','long'],text=True,timeout=60).strip()=='long|10000'
 print(f'{len(reference)} pinned context comparisons ({sum(c['origin']=='original' for c in reference)} original calls); {len(cases)//2} raw paths; duplicate/empty/cycle/timestamp errors and10000-entry context passed')
if __name__=='__main__':main()
