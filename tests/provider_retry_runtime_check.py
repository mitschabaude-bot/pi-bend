"""Native retry effect ownership, seeded jitter, clock and real retry smoke."""
import struct,subprocess,sys,tempfile,time
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve();bun=Path.home()/'.bun/bin/bun'
binary=ROOT/'build/provider-retry-runtime'
if '--no-build' not in sys.argv:
 subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','40','--',str(bun),str(candidate/'main.ts'),'packages/ai/test/provider-retry-runtime.bend','-o',str(binary)+'.c'],cwd=ROOT,check=True)
 subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(binary)+'.c','-lpthread','-lm','-o',str(binary)],check=True)
def scalar(text):
 high,low=map(int,text.split(':'));return struct.unpack('>d',struct.pack('>II',high,low))[0]
# First two words of the separately tested SplitMix64 sequence from seed zero.
def bits(word):
 high,low=struct.unpack('>II',struct.pack('>d',(word>>11)*2**-53));return f'{high}:{low}'
expected_random=[bits(0xe220a8397b1dcdaf),bits(0x6e789e6aa1b965f4)]
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='retry-runtime-') as directory:
 folder=Path(directory)
 source=Path(str(binary)+'.c').read_text()
 source+='''
static void __attribute__((destructor)) runtime_audit(void) {
 u32 timers=0,waiters=0,channels=0;
 for(u32 i=0;i<timer_len;i++){timers+=timer_rows[i].live;waiters+=timer_rows[i].waiter!=NULL;}
 for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
 fprintf(stderr,"RUNTIME_AUDIT %u %u %u\\n",timers,waiters,channels);
}
'''
 (folder/'run.c').write_text(source)
 subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'run')],check=True)
 subprocess.run([str(bun),str(candidate/'main.ts'),'packages/ai/test/provider-retry-runtime.bend','-o',str(folder/'run.js')],cwd=ROOT,check=True)
 for backend,command in [('native-1',[str(folder/'run'),'--threads','1']),('native-4',[str(folder/'run'),'--threads','4']),('bun',[str(bun),str(folder/'run.js')])]:
  before=time.time()*1000
  result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True,timeout=15)
  after=time.time()*1000
  lines=result.stdout.splitlines();assert len(lines)==9,lines
  assert lines[:2]==['random '+v for v in expected_random],lines
  assert lines[2].startswith('now '),lines
  assert before-1000<=scalar(lines[2][4:])<=after+1000,lines[2]
  assert lines[3]=='parsed 1083394048:0',lines
  assert lines[4:8]==['slept','request','request','done ok'],lines
  assert lines[8]=='retained 1083394048:0',lines
  assert result.stderr==('RUNTIME_AUDIT 0 0 0\n' if backend.startswith('native') else ''),result.stderr
  print(backend,'retry runtime PASS',round((after-before)/1000,3),'s',flush=True)
