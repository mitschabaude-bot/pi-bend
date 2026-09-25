"""Port all five original retry tests using a test-only virtual monotonic clock.

The emitted production timer, sleep adapter and retry loop remain unchanged.
Only io_tick and explicit test control effects are supplied by this harness.
"""
from upstream_pin import UPSTREAM
import hashlib,json,re,shutil,subprocess,sys,tempfile
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve();bun=Path.home()/'.bun/bin/bun'
fixture=ROOT/'packages/ai/test/provider-retry-named.bend'
upstream=UPSTREAM / 'packages/ai/test/provider-retry.test.ts'
names=re.findall(r'it\("([^"]+)"',upstream.read_text())
assert len(names)==5
assert all('"'+name+'"' in fixture.read_text() for name in names)
original_tick='''static u64 io_tick(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (u64)ts.tv_sec * 1000000000ull + (u64)ts.tv_nsec;
}'''
virtual_tick='''static u64 test_clock_ns = 1000000000ull;
static u64 io_tick(void) { return test_clock_ns; }'''
records=[]
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='retry-clock-') as directory:
 folder=Path(directory);compiler=folder/'bend2';shutil.copytree(candidate,compiler)
 with (compiler/'base.bend').open('a') as out:out.write((ROOT/'tests/virtual-clock/base.bend').read_text())
 shutil.copyfile(ROOT/'tests/virtual-clock/effect.c',compiler/'effs/test_clock.c')
 subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/provider-retry-named-build.json','--',str(bun),str(compiler/'main.ts'),str(fixture),'-o',str(folder/'run.c')],cwd=ROOT,check=True)
 text=(folder/'run.c').read_text()
 timer=(candidate/'effs/timer.c').read_text();assert timer in text
 assert text.count(original_tick)==1,'review changed runtime clock source'
 text=text.replace(original_tick,virtual_tick)+'\n'+(ROOT/'tests/virtual-clock/controls.c').read_text()
 (folder/'run.c').write_text(text)
 subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'run')],check=True)
 for threads in [1,4]:
  for mode,name in enumerate(names):
   result=subprocess.run([str(folder/'run'),'--threads',str(threads),str(mode)],cwd=ROOT,text=True,capture_output=True,check=True,timeout=10)
   expected=['request']*(2 if mode in [0,3] else 1)+['PASS '+name]
   assert result.stdout.splitlines()==expected,(threads,name,result.stdout)
   assert result.stderr=='CLOCK_AUDIT 0 0 0\n',(threads,name,result.stderr)
   records.append(dict(threads=threads,name=name,audit=result.stderr.strip()))
  print(threads,'threads: five original retry tests PASS',flush=True)
 # Sensitivity control: advance one millisecond too far. The 999/1000 test
 # must now fail its count assertion, proving it observes the actual boundary.
 mutated=text.replace('test_clock_ns += (u64)(u32)fields[0] * 1000000ull;','test_clock_ns += ((u64)(u32)fields[0] + 1) * 1000000ull;')
 assert mutated!=text
 (folder/'early.c').write_text(mutated)
 subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O0','-fbracket-depth=2048',str(folder/'early.c'),'-lpthread','-lm','-o',str(folder/'early')],check=True)
 negative=subprocess.run([str(folder/'early'),'--threads','1','0'],cwd=ROOT,text=True,capture_output=True,timeout=10)
 assert negative.returncode!=0 and 'request count' in negative.stdout+negative.stderr,negative
 print('early-deadline sensitivity control PASS',flush=True)
(ROOT/'build/retry-duration-virtual-clock-result.json').write_text(json.dumps(dict(
 scope='Five original test names/contracts on native one/four threads with virtual io_tick. Production timer code remains byte-identical. Original error identity becomes native original-value preservation. Harness is test-only; no installed compiler changes.',
 source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [fixture,upstream,ROOT/'tests/virtual-clock/base.bend',ROOT/'tests/virtual-clock/effect.c',ROOT/'tests/virtual-clock/controls.c']},
 timer_sha256=hashlib.sha256(timer.encode()).hexdigest(),samples=records,early_deadline_control='failed at request count as required'),indent=2)+'\n')
