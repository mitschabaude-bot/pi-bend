"""Credential transactions across real Node/Bend processes; fake credentials only."""
import argparse,concurrent.futures,json,os,pathlib,selectors,subprocess,tempfile,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--proper-lockfile',type=pathlib.Path,default=ROOT/'build/reference/node_modules/proper-lockfile')
REFERENCE=parser.parse_args().proper_lockfile.resolve()
assert json.loads((REFERENCE/'package.json').read_text())['version']=='4.1.2'
NODE=r'''const fs=require('fs'),lock=require(process.argv[1]);(async()=>{const path=process.argv[2],id=process.argv[3];const release=await lock.lock(path,{realpath:false,retries:{retries:100,minTimeout:10,maxTimeout:50}});try {const data=JSON.parse(fs.readFileSync(path,'utf8'));await new Promise(r=>setTimeout(r,20));data[id]={type:'api_key',key:id};fs.writeFileSync(path,JSON.stringify(data),{mode:0o600});}finally{await release();}})().catch(e=>{console.error(e.message);process.exitCode=1;});'''
for backend,command,probe in [('bun',['bun','build/auth-storage.js'],['bun','build/auth-storage-lock.js']),('native-1',['build/auth-storage','--threads','1'],['build/auth-storage-lock','--threads','1']),('native-4',['build/auth-storage','--threads','4'],['build/auth-storage-lock','--threads','4'])]:
 def run(args,tool=command):
  result=subprocess.run(tool+['--']+args,cwd=ROOT,capture_output=True,text=True,timeout=40)
  assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
  return result.stdout.splitlines()
 with tempfile.TemporaryDirectory(prefix='bend-auth-lock-') as folder:
  path=pathlib.Path(folder)/'auth.json';path.write_text('{}');lock=pathlib.Path(str(path)+'.lock')
  commands=[]
  for n in range(24):
   name=f'provider-{n}'
   commands.append(['node','-e',NODE,str(REFERENCE),str(path),name] if n%2 else command+['--','modify',str(path),name,json.dumps({'type':'api_key','key':name})])
  with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
   results=list(pool.map(lambda c:subprocess.run(c,cwd=ROOT,capture_output=True,text=True,timeout=40),commands))
  assert all(r.returncode==0 and not r.stderr for r in results),(backend,[(r.returncode,r.stderr) for r in results])
  assert json.loads(path.read_text())=={f'provider-{n}':{'type':'api_key','key':f'provider-{n}'} for n in range(24)}
  assert not lock.exists()
  initial={'target':{'type':'api_key','key':'original'},'other':{'type':'api_key','key':'untouched'}}
  for mode in ['cancel','unchanged-cancel','wait-cancel','preabort']:
   path.write_text(json.dumps(initial))
   if mode=='wait-cancel':lock.mkdir()
   start=time.monotonic();lines=run([mode,str(path)],probe)
   assert json.loads(lines[-1])=={'error':'The operation was aborted'},(backend,mode,lines)
   assert time.monotonic()-start<2
   assert json.loads(path.read_text())==initial
   if mode=='wait-cancel':lock.rmdir()
   assert not lock.exists()
  path.write_text(json.dumps(initial))
  process=subprocess.Popen(probe+['--','hold',str(path)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  with selectors.DefaultSelector() as selector:
   selector.register(process.stdout,selectors.EVENT_READ);assert selector.select(10)
   assert process.stdout.readline().strip()=='entered'
  stamp=lock.stat().st_mtime_ns+60_000_000_000;os.utime(lock,ns=(stamp,stamp))
  stdout,stderr=process.communicate(timeout=10)
  assert process.returncode==0 and not stderr
  assert 'compromised' in json.loads(stdout)['error'],(backend,stdout)
  assert json.loads(path.read_text())==initial and lock.exists();lock.rmdir()
  # Failed callbacks/read parsing release the lease, permitting the next writer.
  path.write_text('{invalid')
  assert 'error' in json.loads(run(['modify',str(path),'target','unchanged'])[0])
  assert path.read_text()=='{invalid' and not lock.exists()
  nested=pathlib.Path(folder)/'missing'/'auth.json'
  lines=run(['preabort',str(nested)],probe)
  assert json.loads(lines[-1])=={'error':'The operation was aborted'} and not nested.parent.exists()
 print(f'{backend}: 24 mixed-process updates preserved; cancellation, compromise, malformed-file and cleanup checks passed',flush=True)
