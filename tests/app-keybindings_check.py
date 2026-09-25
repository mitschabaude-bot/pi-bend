#!/usr/bin/env python3
"""Pinned application keybindings source and native filesystem integration."""
from upstream_pin import UPSTREAM
import argparse,itertools,json,random,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(command,inputs):
 p=subprocess.run(command+[json.dumps(inputs,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(p.returncode,p.stderr[-3000:])
 return json.loads(p.stdout)
def raw(command,arg):return json.loads(subprocess.check_output(command+[arg],cwd=ROOT,text=True))
def batch(command,inputs):
 out=[]
 for i in range(0,len(inputs),12):out.extend(run(command,inputs[i:i+12]))
 return out
def corpus(mappings):
 out=[]
 for platform,distro,interop in itertools.product(['linux','darwin','win32','freebsd'],[None,'','Ubuntu'],[None,'','/run/WSL/123']):
  env={'platform':platform,'wslDistroName':distro,'wslInterop':interop}
  out += [{'method':method,'environment':env} for method in ['windows','definitions']]
  for config in [{},{'app.interrupt':'ctrl+x','unknown':[]},{'tui.input.submit':['enter','ctrl+enter'],'app.session.new':[]}]:out.append({'method':'memory','environment':env,'config':config})
 for old,new in mappings.items():
  for config in [{old:'ctrl+x'},{old:'ctrl+x',new:'ctrl+y'},{new:'ctrl+y',old:'ctrl+x'},{old:[], 'unknown.z':True,'unknown.a':{'x':1}}]:out.append({'method':'migration','config':config})
 rng=random.Random(243)
 for _ in range(100):
  names=rng.sample(list(mappings),rng.randrange(8));config={}
  for old in names:
   config[old]=rng.choice(['ctrl+x',[],['up','ctrl+p'],False])
   if rng.randrange(2):config[mappings[old]]=rng.choice(['ctrl+y',None,7])
  config['z.extra']='escape';config['a.extra']='ctrl+q';out.append({'method':'migration','config':config})
 return out
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default=str(UPSTREAM));p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 oracle=['bun','tests/app-keybindings_reference.ts',a.reference]
 originals=raw(oracle,'--original')
 with tempfile.TemporaryDirectory(prefix='pi-app-keys-') as temp:
  inputs=[]
  for i,entry in enumerate(originals):
   case=dict(entry['input'])
   if case['method']=='file':
    folder=Path(temp)/str(i);folder.mkdir();(folder/'keybindings.json').write_text(case.pop('content'));case['agentDir']=str(folder)
   inputs.append(case)
  actual=batch(command,inputs)
  assert len(actual)==len(originals)
  for entry,got in zip(originals,actual):assert entry['expected']==got,(entry,got)
 print(f'{len(originals)} source observations across all 8 named tests passed (two rewrite tests pure-only)',flush=True)
 inputs=corpus(raw(oracle,'--mappings'));expected=batch(oracle,inputs);actual=batch(command,inputs)
 for case,want,got in zip(inputs,expected,actual):
  assert want==got,(case,want,got)
  if case['method']=='migration':assert list(want['config'])==list(got['config']),(case,'migration order',want,got)
 assert len(actual)==len(expected)
 print(f'{len(inputs)} platform/default/migration/manager source comparisons passed',flush=True)
 # Strict loading replaces upstream silently accepting malformed input/resetting defaults.
 with tempfile.TemporaryDirectory(prefix='pi-app-keys-') as temp:
  base=Path(temp);cases=[];expected=[]
  default=run(oracle,[{'method':'memory'}])[0]
  for i,(content,error) in enumerate([(None,None),('{}',None),('\ufeff{"interrupt":"ctrl+x"}',None),('{','json'),('[]','invalid-config'),('null','invalid-config'),('{"app.interrupt":1}','invalid-binding'),('{"app.interrupt":["escape",false]}','invalid-binding'),('{"app.interrupt":"unknown+q"}','invalid-key'),('{"unknown":"ctrl+q"}',None),('{"app.interrupt":"ctrl+x","app.interrupt":"ctrl+y"}',None),(b'\xff','utf8')]):
   folder=base/str(i);folder.mkdir();path=folder/'keybindings.json'
   if content is not None:path.write_bytes(content if isinstance(content,bytes) else content.encode())
   cases.append({'method':'file','agentDir':str(folder)})
   if error:expected.append({'error':error})
   else:
    config={} if content is None else json.loads(content.lstrip('\ufeff'));migrated=run(oracle,[{'method':'migration','config':config}])[0]['config'];expected.append(run(oracle,[{'method':'memory','config':migrated}])[0])
  folder=base/'directory';folder.mkdir();(folder/'keybindings.json').mkdir();cases.append({'method':'file','agentDir':str(folder)});expected.append({'error':'filesystem'})
  actual=batch(command,cases)
  for c,w,g in zip(cases,expected,actual):assert w==g,(c,w,g)
  reload_cases=[]
  for i,replacement in enumerate(['{"app.interrupt":"ctrl+y"}','{}','{','{"app.interrupt":false}']):
   folder=base/f'reload{i}';folder.mkdir();(folder/'keybindings.json').write_text('{"interrupt":"ctrl+x"}')
   reload_cases.append({'method':'reload','agentDir':str(folder),'replacement':replacement})
  got=batch(command,reload_cases);before=run(oracle,[{'method':'memory','config':{'app.interrupt':'ctrl+x'}}])[0]
  for i,item in enumerate(got):
   assert item['before']==before and item['retained']==before,(i,item)
   want=run(oracle,[{'method':'memory','config':{'app.interrupt':'ctrl+y'} if i==0 else {}}])[0] if i<2 else {'error':'json' if i==2 else 'invalid-binding'}
   assert item['after']==want,(i,want,item)
  for case in cases[:12]:
   # Loading alone must never rewrite migrations or strip BOM on disk.
   i=int(Path(case['agentDir']).name)
   if i==2:assert (Path(case['agentDir'])/'keybindings.json').read_bytes().startswith(b'\xef\xbb\xbf')
 print('13 real file loading/error cases and 4 retained-state reload cases passed',flush=True)
