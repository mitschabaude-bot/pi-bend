"""Correctness/lifetime checks for the isolated additive timer experiment."""
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import hashlib,json,shutil,subprocess,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
baseline=TOOLCHAIN
bun=Path.home()/'.bun/bin/bun'
addition=ROOT/'patches/experimental/timer'
assert (candidate/'base.bend').read_bytes()==(baseline/'base.bend').read_bytes()+(addition/'base.bend').read_bytes()
for p in baseline.rglob('*'):
    if p.is_file() and p.relative_to(baseline)!=Path('base.bend'):assert p.read_bytes()==(candidate/p.relative_to(baseline)).read_bytes(),p
for name in ['timer.c','timer.js']:assert (candidate/'effs'/name).read_bytes()==(addition/name).read_bytes()
results={}
with tempfile.TemporaryDirectory(prefix='timer-check-',dir=ROOT/'build') as directory:
    folder=Path(directory)
    compiler=folder/'bend2';shutil.copytree(candidate,compiler)
    # Audit only in this disposable copy. No instrumentation is installed or
    # included in the production candidate's hot paths.
    timer_source=compiler/'effs/timer.c'
    timer_source.write_text(timer_source.read_text().replace('static Term timer_ready(', 'static u32 timer_expirations;\nstatic Term timer_ready(').replace('  row->state = 1;\n  row->waiter = NULL;', '  timer_expirations++;\n  row->state = 1;\n  row->waiter = NULL;'))
    with (compiler/'effs/timer.c').open('a') as out:
        out.write('''\nstatic void __attribute__((destructor)) timer_audit(void) {
  u32 live=0, waiting=0;
  for (u32 i=0;i<timer_len;i++) { live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL; }
  fprintf(stderr,"TIMER_AUDIT %u %u %u %u\\n",timer_len,live,waiting,timer_expirations);
}\n''')
    source=ROOT/'tests/timer-primitive.bend'
    subprocess.run([str(bun),str(compiler/'main.ts'),str(source),'-o',str(folder/'timer.c')],cwd=ROOT,check=True)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'timer.c'),'-lpthread','-lm','-o',str(folder/'timer')],check=True)
    for threads in [1,4]:
        start=time.monotonic()
        run=subprocess.run([str(folder/'timer'),'--threads',str(threads)],capture_output=True,text=True,timeout=5,check=True)
        assert run.stdout=='PASS timer primitive\n',run.stdout
        assert run.stderr=='TIMER_AUDIT 3 0 0 1\n',run.stderr
        results[str(threads)]={'seconds':time.monotonic()-start,'stdout':run.stdout,'audit':run.stderr}
    subprocess.run([str(bun),str(candidate/'main.ts'),str(source),'-o',str(folder/'timer.js')],cwd=ROOT,check=True)
    run=subprocess.run([str(bun),str(folder/'timer.js')],capture_output=True,text=True,timeout=5,check=True)
    assert run.stdout=='PASS timer primitive\n',run.stdout
    results['js']={'stdout':run.stdout}
    rejected=folder/'copy.bend'
    rejected.write_text('import Base\n\ndef bad(+owner: Timer) -> Timer & Timer: (owner, owner)\n')
    run=subprocess.run([str(bun),str(candidate/'main.ts'),str(rejected)],capture_output=True,text=True,timeout=20)
    assert run.returncode!=0 and ('Data' in run.stdout+run.stderr or 'copy' in run.stdout+run.stderr),run.stdout+run.stderr
    results['owner_copy_rejected']=True
    # Reachability must not require unused timer effect constructors.
    small=folder/'close-only.bend'
    small.write_text('''import Base

def close(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case Tuple{owner, cancel}: Timer.close(owner)

def main() -> IO(Unit):
  do IO<Unit>:
    pair : Timer & TimerCancel <- Timer.new(60000)
    close(pair)
''')
    subprocess.run([str(bun),str(candidate/'main.ts'),str(small),'-o',str(folder/'small.c')],check=True)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O1',str(folder/'small.c'),'-lpthread','-lm','-o',str(folder/'small')],check=True)
    subprocess.run([str(folder/'small')],check=True,timeout=5)
    results['new_close_only']=True
results['source_sha256']=hashlib.sha256((ROOT/'tests/timer-primitive.bend').read_bytes()).hexdigest()
results['scope']='Core ownership/one-shot semantics, parked cancellation, queue removal, 10000 serial lifecycles. Not full race/performance acceptance.'
print(json.dumps(results,indent=2))
