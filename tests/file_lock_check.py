"""Actual interprocess proper-lockfile interoperability and owned lease lifecycle."""
import argparse,concurrent.futures,json,os,selectors,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--proper-lockfile',type=Path,default=ROOT/'build/reference/node_modules/proper-lockfile');a=p.parse_args()
 assert json.loads((a.proper_lockfile/'package.json').read_text())['version']=='4.1.2'
 cmd=['bun',str(Path(a.runner).resolve())] if a.runner.endswith('.js') else [str(Path(a.runner).resolve()),'--threads',a.threads]
 reference=['node',str(ROOT/'tests/file_lock_reference.cjs'),str(a.proper_lockfile)]
 checks=0
 def run(args,expected,timeout=10,env=None):
  nonlocal checks
  r=subprocess.run([*cmd,'--',*map(str,args)],text=True,capture_output=True,timeout=timeout,env=env)
  assert r.returncode==0 and not r.stderr,(args,r.returncode,r.stderr)
  assert r.stdout.splitlines()==expected,(args,r.stdout,expected)
  checks+=1
 def read_line(proc):
  with selectors.DefaultSelector() as s:
   s.register(proc.stdout,selectors.EVENT_READ);assert s.select(10),'holder did not become ready'
   return proc.stdout.readline().strip()
 def holder(args):
  proc=subprocess.Popen(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  assert read_line(proc)=='acquired',args
  return proc
 def finish(proc,expected):
  nonlocal checks
  out,err=proc.communicate(timeout=10);assert proc.returncode==0 and not err,(proc.returncode,out,err)
  assert out.splitlines()==expected,(out,expected);checks+=1
 with tempfile.TemporaryDirectory(prefix='bend-file-lock-') as temporary:
  path=Path(temporary)/'settings 雪.json';lock=Path(str(path)+'.lock')
  run(['hold',path,0],['acquired','check:ok','release:ok']);assert not lock.exists()
  run(['defaults',path],['acquire:path:2']);path.write_text('0')
  run(['defaults',path],['acquired','check:ok','release:ok'])
  alias=Path(temporary)/'alias';alias.symlink_to(path)
  node=holder([*reference,'hold',str(path),'300'])
  run(['defaults',alias],['acquire:locked']);run(['hold',alias,0],['acquired','check:ok','release:ok'])
  run(['hold',os.path.relpath(path,Path.cwd()),0],['acquire:locked']);finish(node,['released'])
  for millis in [-1001,-1,0,1700000000123]:
   word=millis%(1<<64);seconds,remainder=divmod(millis,1000);seconds%=1<<64
   run(['metadata',path,word>>32,word&0xffffffff],['ok',f'{seconds>>32}:{seconds&0xffffffff}:{remainder*1000000}'])
   assert path.stat().st_mtime_ns==millis*1000000
  run(['nul',path],['error:84|error:84|error:84|stat:84'])
  nanoseconds=1700000000123456789;os.utime(path,ns=(nanoseconds,nanoseconds))
  run(['stat',path],['0:1700000000:123456789'])
  overflow=8640000000000001
  run(['metadata',path,overflow>>32,overflow&0xffffffff],['error:75','0:1700000000:123456789'])


  run(['invalid',path],['acquire:options']);assert not lock.exists()
  run(['pre',path],['acquire:cancelled']);assert not lock.exists()
  run(['pre-realpath',str(path)+'.absent'],['acquire:cancelled'])
  # Node holds beyond stale timeout; its heartbeat must prevent native takeover.
  node=holder([*reference,'hold',str(path),'2700'])
  time.sleep(2.15);run(['hold',path,0],['acquire:locked']);finish(node,['released']);assert not lock.exists()
  # Native holds beyond stale timeout; proper-lockfile must see its updates.
  bend=holder([*cmd,'--','hold',str(path),'2700'])
  original=lock.stat().st_mtime_ns;time.sleep(2.15);assert lock.stat().st_mtime_ns!=original
  r=subprocess.run([*reference,'hold',str(path),'0'],text=True,capture_output=True,timeout=10);assert r.stdout.splitlines()==['locked'] and not r.stderr
  finish(bend,['check:ok','release:ok']);assert not lock.exists()
  # Settings' fixed retries wait for another process to release.
  node=holder([*reference,'hold',str(path),'80'])
  run(['retry',path],['acquired','check:ok','release:ok']);finish(node,['released'])
  lock.mkdir();start=time.monotonic();run(['retry',path],['acquire:locked']);elapsed=time.monotonic()-start
  assert .15<=elapsed<2,elapsed
  # Cancellation interrupts a five-second retry delay, retiring its observer/timer.
  start=time.monotonic();run(['cancel',path],['acquire:cancelled']);assert time.monotonic()-start<1
  lock.rmdir()
  # Staleness, including the seconds-precision case, uses the shared lock directory.
  lock.mkdir();past=time.time()-5;os.utime(lock,(past,past));run(['hold',path,0],['acquired','check:ok','release:ok'])
  lock.mkdir();past=int(time.time())-5;os.utime(lock,(past,past));run(['hold',path,0],['acquired','check:ok','release:ok'])
  # Kill each implementation; the surviving implementation reclaims the stale lease.
  node=holder([*reference,'hold',str(path),'10000']);node.kill();node.communicate(timeout=5);assert lock.exists()
  os.utime(lock,(time.time()-5,time.time()-5));run(['hold',path,0],['acquired','check:ok','release:ok'])
  bend=holder([*cmd,'--','hold',str(path),'10000']);bend.kill();bend.communicate(timeout=5);assert lock.exists()
  os.utime(lock,(time.time()-5,time.time()-5));r=subprocess.run([*reference,'hold',str(path),'0'],text=True,capture_output=True,timeout=5);assert r.stdout.splitlines()==['acquired','released'] and not r.stderr
  # A changed lease is sticky even if someone subsequently restores its old mtime.
  bend=holder([*cmd,'--','hold',str(path),'1700']);old=lock.stat().st_mtime_ns
  os.utime(lock,ns=(old+20_000_000_000,old+20_000_000_000));time.sleep(1.2);os.utime(lock,ns=(old,old))
  finish(bend,['check:compromised:modified','release:compromised:modified']);assert lock.exists();lock.rmdir()
  # Release/check cannot remove a replacement owner's directory.
  bend=holder([*cmd,'--','hold',str(path),'150']);lock.rmdir();lock.mkdir();future=time.time()+30;os.utime(lock,(future,future))
  finish(bend,['check:compromised:modified','release:compromised:modified']);assert lock.exists();lock.rmdir()
  bend=holder([*cmd,'--','hold',str(path),'150']);lock.rmdir()
  finish(bend,['check:compromised:missing','release:compromised:missing']);assert not lock.exists()
  # Genuine mixed-process contention: every read/modify/write must survive.
  path.write_text('0')
  commands=[[*reference,'increment',str(path)] if i%2 else [*cmd,'--','increment',str(path)] for i in range(30)]
  with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
   results=list(pool.map(lambda c:subprocess.run(c,text=True,capture_output=True,timeout=20),commands))
  for r in results:assert r.returncode==0 and not r.stderr and r.stdout.splitlines()==['increment:ok'],(r.returncode,r.stdout,r.stderr)
  assert path.read_text()=='30',path.read_text();assert not lock.exists();checks+=1
  run(['repeat',path],['repeat:ok']);assert not lock.exists()
  # Lock path shape errors do not silently become mutual exclusion.
  lock.write_text('not a directory');run(['hold',path,0],['acquire:locked']);lock.unlink()
  lock.mkdir();(lock/'child').write_text('occupied');os.utime(lock,(time.time()-5,time.time()-5));run(['hold',path,0],['acquire:rmdir:39'])
  (lock/'child').unlink();lock.rmdir()
  if not a.runner.endswith('.js'):
   library=Path(temporary)/'faults.so'
   subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/file_lock_faults.c'),'-ldl','-o',str(library)],check=True)
   def fault(variables,duration,expected):
    env={**os.environ,'LD_PRELOAD':str(library),**variables}
    run(['hold',path,duration],expected,env=env)
    if lock.exists():lock.rmdir()
   fault({'BEND_LOCK_STAT_FAIL':'1'},0,['acquire:stat:13'])
   fault({'BEND_LOCK_TOUCH_FAIL':'1'},0,['acquire:utimes:13'])
   fault({'BEND_LOCK_TOUCH_FAIL':'1','BEND_LOCK_REMOVE_FAIL':'1'},0,['acquire:cleanup:utimes:13:rmdir:5'])
   fault({'BEND_LOCK_REMOVE_FAIL':'1'},0,['acquired','check:ok','release:rmdir:5'])
   fault({'BEND_LOCK_STAT_FAIL':'2'},2500,['acquired','check:ok','release:ok'])
   fault({'BEND_LOCK_TOUCH_FAIL':'2'},2500,['acquired','check:ok','release:ok'])
   fault({'BEND_LOCK_STAT_FAIL':'2+'},3200,['acquired','check:compromised:update:13','release:compromised:update:13'])
   fault({'BEND_LOCK_TOUCH_FAIL':'2+'},3200,['acquired','check:compromised:update:13','release:compromised:update:13'])
   fault({'BEND_LOCK_SECONDS':'1'},2500,['acquired','check:ok','release:ok'])
   fault({'BEND_LOCK_TOUCH_DELAY':'1'},1200,['acquired','check:ok','release:ok'])
   run(['cancel',path],['acquire:cancelled'],env={**os.environ,'LD_PRELOAD':str(library),'BEND_LOCK_PROBE_DELAY':'1'})
   assert not lock.exists()
   run(['cancel',path],['acquire:cleanup:utimes:13:rmdir:5'],env={**os.environ,'LD_PRELOAD':str(library),'BEND_LOCK_PROBE_DELAY':'1','BEND_LOCK_TOUCH_FAIL':'1','BEND_LOCK_REMOVE_FAIL':'1'})
   assert lock.exists();lock.rmdir()


 print(f'{checks} lifecycle/interprocess checks passed, including 30 mixed Node/Bend increments and 100 acquire/release cycles')
if __name__=='__main__':main()
