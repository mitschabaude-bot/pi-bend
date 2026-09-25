"""Stress the isolated timer experiment; audit all created timers are retired."""
import subprocess,sys,tempfile,shutil
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
bun=Path.home()/'.bun/bin/bun'
source=ROOT/'tests/timer-races.bend'
baseline=TOOLCHAIN
addition=ROOT/'patches/experimental/timer'
assert (candidate/'base.bend').read_bytes()==(baseline/'base.bend').read_bytes()+(addition/'base.bend').read_bytes()
for path in baseline.rglob('*'):
    if path.is_file() and path.relative_to(baseline)!=Path('base.bend'):
        assert path.read_bytes()==(candidate/path.relative_to(baseline)).read_bytes(),path
for name in ['timer.c','timer.js']:assert (candidate/'effs'/name).read_bytes()==(addition/name).read_bytes()
with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='timer-races-') as directory:
    folder=Path(directory);compiler=folder/'bend2';shutil.copytree(candidate,compiler)
    path=compiler/'effs/timer.c';text=path.read_text()
    text='static unsigned long long timer_created, timer_closed, timer_expired, timer_cancelled;\n'+text
    text=text.replace('  row->gen += 1;','  timer_created++;\n  row->gen += 1;').replace('row->state = 1;','timer_expired++; row->state = 1;').replace('  row->state = 2;','  timer_cancelled++; row->state = 2;').replace('  row->live = 0;','  timer_closed++; row->live = 0;')
    text+='''\nstatic void __attribute__((destructor)) timer_audit(void) {
  u32 live=0,waiting=0;
  for(u32 i=0;i<timer_len;i++){ live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL; }
  fprintf(stderr,"TIMER_AUDIT %llu %llu %llu %llu %u %u %u\\n",timer_created,timer_closed,timer_expired,timer_cancelled,live,waiting,timer_len);
}\n'''
    path.write_text(text)
    path=compiler/'effs/timer.js';text=path.read_text()
    text='const audit={created:0,closed:0,expired:0,cancelled:0,waiters:0};\n'+text
    text=text.replace('  const row = { deadline:', '  audit.created++;\n  const row = { deadline:').replace('row.state = 1;','audit.expired++; row.state = 1;').replace('row.state = 2;','audit.cancelled++; row.state = 2;').replace('row.state = 3;','audit.closed++; row.state = 3;')
    text=text.replace('  row.waiter = wait;','  audit.waiters++;\n  row.waiter = wait;').replace('row.waiter = null;','audit.waiters--; row.waiter = null;')
    text+="\nprocess.on('exit',()=>console.error('TIMER_AUDIT',audit.created,audit.closed,audit.expired,audit.cancelled,audit.created-audit.closed,audit.waiters));\n"
    path.write_text(text)
    for suffix in ['c','js']:
        subprocess.run([str(bun),str(compiler/'main.ts'),str(source),'-o',str(folder/('run.'+suffix))],cwd=ROOT,check=True)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'run')],check=True)
    for backend,command in [('native-1',[str(folder/'run'),'--threads','1']),('native-4',[str(folder/'run'),'--threads','4']),('bun',[str(bun),str(folder/'run.js')])]:
        for rounds,size in [(10,1),(10,128),(5,1024)]:
            run=subprocess.run([*command,str(rounds),str(size)],text=True,capture_output=True,check=True,timeout=30)
            assert run.stdout=='PASS timer races and batches\n',run.stdout
            fields=run.stderr.split();assert fields[0]=='TIMER_AUDIT',run.stderr
            counts=list(map(int,fields[1:]));created,closed,expired,cancelled,live,waiting=counts[:6]
            assert created==closed==272+rounds*size,(backend,counts)
            assert expired+cancelled==created and expired>0 and cancelled>0,(backend,counts)
            assert live==waiting==0,(backend,counts)
            if backend.startswith('native'):assert counts[6]==size,(backend,counts)
            print(backend,rounds,size,'PASS',flush=True)
