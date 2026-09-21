"""Run retry traces with real native timers and audit cancellation/retirement.

Uses the isolated timer compiler. Real-time tests supplement, rather than
replace, upstream virtual-clock boundary assertions.
"""
import hashlib,json,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1]).resolve()
bun=Path.home()/'.bun/bin/bun'
binary=ROOT/'build/provider-retry-native-sleep'
if '--no-build' not in sys.argv:
 subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','40','--',str(bun),str(candidate/'main.ts'),'packages/ai/test/provider-retry-native-sleep.bend','-o',str(binary)+'.c'],cwd=ROOT,check=True)
 subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(binary)+'.c','-lpthread','-lm','-o',str(binary)],check=True)
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/provider_retry_reference.mts'],cwd=ROOT,text=True))
# Approved strict-input adaptation: upstream setTimeout turns a NaN delay into
# 1ms and retries. The native adapter instead rejects before allocating a timer.
assert expected[11]=='request\ndate invalid-date\nnow\nsleep 2146959360:0\nrequest\ndone ok\n'
expected[11]='request\ndate invalid-date\nnow\nsleep 2146959360:0\ninvalid-sleep-duration\n'

source=(candidate/'effs/timer.c').read_text()
text=Path(str(binary)+'.c').read_text()
assert source in text,'generated timer effect differs from candidate'
audit='static unsigned long long audit_created, audit_cancelled_parked;\n'+source
assert '  row->gen += 1;' in audit
assert '  row->state = 2;' in audit
audit=audit.replace('  row->gen += 1;','  audit_created++;\n  row->gen += 1;').replace('  row->state = 2;','  audit_cancelled_parked += row->waiter != NULL;\n  row->state = 2;')
text=text.replace(source,audit)
text+='''
static void __attribute__((destructor)) retry_timer_audit(void) {
 u32 live=0,waiting=0,channels=0;
 for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
 for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
 fprintf(stderr,"RETRY_TIMER_AUDIT %llu %llu %u %u %u\\n",audit_created,audit_cancelled_parked,live,waiting,channels);
}
'''
records=[]
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='retry-timer-audit-') as directory:
 folder=Path(directory);(folder/'run.c').write_text(text)
 for suffix in ['c','js']:
  subprocess.run([str(bun),str(candidate/'main.ts'),'packages/ai/test/provider-retry-sleep.bend','-o',str(folder/('smoke.'+suffix))],cwd=ROOT,check=True)
 subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'smoke.c'),'-lpthread','-lm','-o',str(folder/'smoke')],check=True)
 for command in [[str(folder/'smoke'),'--threads','1'],[str(folder/'smoke'),'--threads','4'],[str(bun),str(folder/'smoke.js')]]:
  smoke=subprocess.run(command,capture_output=True,text=True,check=True,timeout=10)
  assert smoke.stdout=='PASS provider sleep\n' and not smoke.stderr,smoke
 print('provider sleep: native 1/4 and Bun PASS',flush=True)
 subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'run')],check=True)
 for threads in [1,4]:
  for mode,trace in enumerate(expected):
   start=time.monotonic();result=subprocess.run([str(folder/'run'),'--threads',str(threads),str(mode)],cwd=ROOT,capture_output=True,text=True,check=True,timeout=10)
   elapsed=time.monotonic()-start
   assert result.stdout==trace,(threads,mode,result.stdout,trace)
   created=[1,0,0,1,1,0,0,2,0,0,1,0][mode]
   cancelled=1 if mode==4 else 0
   assert result.stderr==f'RETRY_TIMER_AUDIT {created} {cancelled} 0 0 0\n',(threads,mode,result.stderr)
   records.append(dict(threads=threads,mode=mode,seconds=elapsed,created=created,cancelled_parked=cancelled,live=0,waiting=0,channels=0))
  print(threads,'threads: 12 real-timer retry traces and cleanup PASS',flush=True)
(ROOT/'build/retry-duration-native-timers-result.json').write_text(json.dumps(dict(scope='Real native timers plus instrumented lifetime checks; not a performance comparison or virtual-time boundary proof.',source_sha256=hashlib.sha256(text.encode()).hexdigest(),timer_sha256=hashlib.sha256(source.encode()).hexdigest(),samples=records),indent=2)+'\n')
