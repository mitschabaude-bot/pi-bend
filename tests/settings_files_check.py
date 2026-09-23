#!/usr/bin/env python3
"""Real native settings files: no-create reads, strict errors, locks and merges."""
import argparse,json,subprocess,tempfile,concurrent.futures
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 assert command
 checks=0
 with tempfile.TemporaryDirectory(prefix='bend-settings-') as tmp:
  base=Path(tmp);cwd=base/'project';agent=base/'agent';cwd.mkdir()
  def run(**kw):
   args={'cwd':str(cwd),'agentDir':str(agent),**kw}
   value=subprocess.run(command+[json.dumps(args)],capture_output=True,text=True,cwd=ROOT,timeout=30)
   assert value.returncode==0,(value.returncode,value.stderr)
   return json.loads(value.stdout)
  assert run()=={'global':{},'project':{},'errors':[],'errorPaths':[]};assert not agent.exists() and not (cwd/'.pi').exists();checks+=1
  result=run(key='theme',value='dark');assert result['global']=={'theme':'dark'} and result['errors']==[];checks+=1
  file=agent/'settings.json';assert json.loads(file.read_text())=={'theme':'dark'};assert not (agent/'settings.json.lock').exists();checks+=1
  file.write_text(json.dumps({'theme':'external','skills':[],'unknown':{'a':1}}))
  assert run(key='quietStartup',value=True)['errors']==[]
  assert json.loads(file.read_text())=={'theme':'external','skills':[],'unknown':{'a':1},'quietStartup':True};checks+=1
  for malformed,error in [(b'{','json'),(b'{"theme":3}','setting'),(b'{"theme":"a","theme":"b"}','duplicate'),(b'{"theme":"\xff"}','utf8')]:
   file.write_bytes(malformed);result=run(key='theme',value='must-not-write');assert result['errors']==['global.'+error],result;assert file.read_bytes()==malformed;assert result['errorPaths']==[str(file)];checks+=1
  file.write_text('{"theme":"good"}')
  file.chmod(0o444)
  try:
   result=run(key='theme',value='write-failed');assert result['errors']==['global.filesystem'] and result['global']['theme']=='write-failed',result
   assert json.loads(file.read_text())=={'theme':'good'};assert not (agent/'settings.json.lock').exists();checks+=1
  finally:file.chmod(0o644)
  project=cwd/'.pi';project.mkdir();pfile=project/'settings.json';pfile.write_text('{"theme":"untrusted"}')
  assert run(trusted=False)['project']=={};assert run()['project']=={'theme':'untrusted'};checks+=1
  assert run(trusted=False,project=True,key='skills',value=['blocked'])['errors']==['global.untrusted'];assert json.loads(pfile.read_text())=={'theme':'untrusted'};checks+=1
  assert run(project=True,key='skills',value=['ok'])['errors']==[];assert json.loads(pfile.read_text())=={'theme':'untrusted','skills':['ok']};checks+=1
  # Concurrent distinct dirty fields must preserve both even on first creation.
  file.unlink()
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
   results=list(pool.map(lambda kv:run(key=kv[0],value=kv[1]),[('theme','new'),('quietStartup',True)]))
  assert all(not r['errors'] for r in results),results
  assert json.loads(file.read_text())=={'theme':'new','quietStartup':True};checks+=1
  lock=agent/'settings.json.lock';lock.mkdir()
  result=run(key='theme',value='blocked');assert result['errors']==['global.lock'],result;assert json.loads(file.read_text())['theme']=='new';lock.rmdir();checks+=1
  # A broken file parent surfaces a typed failure without creating a lock.
  other=base/'not-a-directory';other.write_text('data')
  result=run(agentDir=str(other),key='theme',value='x');assert result['errors']==['global.filesystem'],result;checks+=1
  assert not list(base.rglob('*.lock'));checks+=1
 print(f'{checks} real-file settings checks passed')
if __name__=='__main__':main()
