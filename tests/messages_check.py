"""Pinned message text and strict zoned timestamp compatibility."""
import argparse,datetime,json,random,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def wire(s):return ','.join(str(ord(c)) for c in s)
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');a=p.parse_args()
 cmd=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 rng=random.Random(382);cases=[];commands=[]
 dates=['1970-01-01T00:00:00Z','1969-12-31T23:59:59.999Z','0000-02-29T00:00:00Z','9999-12-31T23:59:59.999Z','2000-02-29T12:34:56.123456789+05:30','2024-01-01T00:00:00-23:59']
 for _ in range(180):
  d=datetime.datetime(rng.randrange(1,10000),rng.randrange(1,13),rng.randrange(1,29),rng.randrange(24),rng.randrange(60),rng.randrange(60))
  dates.append(f'{d.year:04}-{d.month:02}-{d.day:02}T{d.hour:02}:{d.minute:02}:{d.second:02}.'+''.join(str(rng.randrange(10)) for _ in range(rng.randrange(1,4)))+rng.choice(['Z','+00:00','-03:30','+14:00']))
 for timestamp in dates:cases.append(dict(kind='date',timestamp=timestamp));commands.append('d|'+timestamp)
 for output in ['', 'hello','line\n','```\nstrange`é']:
  for exit in [None,0,7,137]:
   for cancelled in [False,True]:
    for truncated in [False,True]:
     for path in [None,'','/tmp/full']:
      m=dict(command='printf `x`',output=output,exitCode=exit,cancelled=cancelled,truncated=truncated,fullOutputPath=path)
      cases.append(dict(kind='bash',message=m));commands.append('|'.join(['b',wire(m['command']),wire(output),'none' if exit is None else str(exit),str(int(cancelled)),str(int(truncated)),'none' if path is None else wire(path)]))
 with tempfile.TemporaryDirectory() as tmp:
  f=Path(tmp)/'cases.json';f.write_text(json.dumps(cases));oracle=[json.loads(x) for x in subprocess.check_output(['bun',str(ROOT/'tests/messages_reference.ts'),str(ROOT.parent/'pi-mono/packages/coding-agent/src'),str(f)],text=True).splitlines()]
 wanted=[str(v) if c['kind']=='date' else wire(v) for c,v in zip(cases,oracle)]
 for start in range(0,len(commands),80):
  r=subprocess.run([*cmd,*commands[start:start+80]],text=True,capture_output=True,timeout=30)
  assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
  assert r.stdout.splitlines()==wanted[start:start+80],[(commands[start+i],x,wanted[start+i]) for i,x in enumerate(r.stdout.splitlines()) if x!=wanted[start+i]][:5]
 fractions=['000123456789','0597925507326','123456789123456789','999999999999999999','100000000000000000','0'*1000+'123']
 rows=subprocess.check_output([*cmd,*['d|1970-01-01T00:00:00.'+v+'Z' for v in fractions]],text=True).splitlines()
 assert rows==[str(int(v[:3])) for v in fractions],rows
 invalid=['','2024-01-01','2024-01-01T00:00:00','2023-02-29T00:00:00Z','1900-02-29T00:00:00Z','2024-04-31T00:00:00Z','2024-01-01T24:00:00Z','2024-01-01T00:00:60Z','2024-01-01T00:00:00.Z','2024-01-01T00:00:00.1xZ','2024-01-01T00:00:00+24:00','2024-01-01T00:00:00+00:60','2024-01-01T00:00:00+0000',' 2024-01-01T00:00:00Z','2024-01-01T00:00:00Zjunk','+010000-01-01T00:00:00Z','2024-1-01T00:00:00Z']
 out=subprocess.check_output([*cmd,*['d|'+v for v in invalid]],text=True).splitlines();assert out==['error']*len(invalid)
 for d in [dates[0],dates[1],dates[4],invalid[3]]:
  rows=subprocess.check_output([*cmd,'c|'+d],text=True).splitlines()
  if d in invalid:assert rows==['error']*3
  else:
   epoch=wanted[dates.index(d)];assert rows==[wire('summary')+'|id|'+epoch,wire('summary')+'|123|'+epoch,'custom|'+wire('body')+'|0|details|'+epoch],rows
 rows=subprocess.check_output([*cmd,'convert'],text=True).splitlines()
 branch='The following is a summary of a branch that this conversation came back from:\n\n<summary>\nbranch</summary>'
 compact='The conversation history before this point was compacted into the following summary:\n\n<summary>\ncompact\n</summary>'
 bash='Ran `ls`\n```\nfile\n```\n\nCommand exited with code 7\n\n[Output truncated. Full output: /tmp/full]'
 assert rows==['original|'+wire('original')+'|1','user|t:'+wire('hidden still in context')+'|3','user|t:'+wire('caption')+';i:YWJj:image/png|4','user|t:'+wire(branch)+'|5','user|t:'+wire(compact)+'|6','user|t:'+wire(bash)+'|7'],rows
 print(f'{len(cases)} pinned comparisons; {len(invalid)} invalid/range cases; constructors and ordered typed conversion passed')
if __name__=='__main__':main()
