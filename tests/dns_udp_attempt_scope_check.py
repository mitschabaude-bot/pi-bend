"""Nested UDP attempt deadlines preserve total/caller reasons and retire every timer/observer."""
import hashlib,json,re,subprocess,time
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';candidate=TOOLCHAIN;stem='dns-udp-attempt-scope'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{stem}-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),f'tests/{stem}.bend','-o',f'build/{stem}.{suffix}'],cwd=ROOT,check=True)
source=(ROOT/f'build/{stem}.c').read_text();timer=(candidate/'effs/timer.c').read_text();assert source.count(timer)==1
assert timer.count('  row->gen += 1;')==1
source=source.replace(timer,'static unsigned udp_test_created;\n'+timer.replace('  row->gen += 1;','  udp_test_created++;\n  row->gen += 1;'))
source+='''
static void __attribute__((destructor)) udp_scope_audit(void) {
  unsigned live=0,waiting=0,channels=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u %u %u %u\\n",udp_test_created,live,waiting,channels,io_park.head!=NULL);
}
'''
(ROOT/f'build/{stem}-audit.c').write_text(source)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{stem}-audit.c','-lpthread','-lm','-o',f'build/{stem}'],cwd=ROOT,check=True)
source=(ROOT/f'build/{stem}.js').read_text();timer=(candidate/'effs/timer.js').read_text();assert source.count(timer)==1
assert timer.count('  const row = { deadline:')==1 and timer.count('  row.state = 3;')==1
timer='const scopeAudit={created:0,closed:0};\n'+timer.replace('  const row = { deadline:','  scopeAudit.created++;\n  const row = { deadline:').replace('  row.state = 3;','  scopeAudit.closed++;\n  row.state = 3;')
timer+='\nprocess.on("exit",()=>console.error(`AUDIT ${scopeAudit.created} ${scopeAudit.created-scopeAudit.closed} ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'
source=source.replace((candidate/'effs/timer.js').read_text(),timer);(ROOT/f'build/{stem}-audit.js').write_text(source)
rows=[]
for backend,command in [('native 1',[f'build/{stem}','--threads','1']),('native 4',[f'build/{stem}','--threads','4']),('Bun',[str(bun),f'build/{stem}-audit.js'])]:
    for mode in ['active','maximum','invalid','pre','pre-default','later','total','attempt']:
        for count in ([1] if mode=='attempt' else [1,20]):
            expected={'active':['closed:active'],'maximum':['closed:active'],'invalid':['invalid'],'pre':['observed:caller:stop','closed:caller:stop'],'pre-default':['observed:caller:default','closed:caller:default'],'later':['observed:caller:stop','closed:caller:stop'],'total':['observed:total','closed:total'],'attempt':['observed:attempt','closed:attempt']}[mode]*count
            expected_created=0 if mode in ['pre','pre-default'] else 1 if mode=='invalid' else count+1 if mode in ['active','maximum'] else 2
            start=time.monotonic();run=subprocess.run([*command,mode,str(count)],cwd=ROOT,capture_output=True,text=True,timeout=10);elapsed=time.monotonic()-start
            fields=run.stderr.split()
            assert len(fields)==(5 if backend=='Bun' else 6) and fields[0]=='AUDIT',(backend,run)
            created=int(fields[1])
            # Parent forwarding can settle before child creation on a busy host.
            if mode=='later':assert 0<=created<=2
            elif mode=='total':assert 1<=created<=2
            else:assert created==expected_created
            audit=f'AUDIT {created} 0 0 0\n' if backend=='Bun' else f'AUDIT {created} 0 0 0 0\n'
            assert run.returncode==0 and run.stdout.splitlines()==expected and run.stderr==audit,(backend,mode,count,run)
            if mode=='attempt':assert elapsed>=0.9,'one-second attempt expired too early'
            rows.append(dict(backend=backend,mode=mode,count=count,seconds=elapsed,created_timers=created,audit=run.stderr.strip()))
    print(f'{backend}: 15 nested deadline scenarios PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/f'tests/{stem}.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_udp_attempt_scope_check.py',f'build/{stem}-audit.c',f'build/{stem}-audit.js']
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend','effs/timer.c','effs/timer.js']},builds={s:json.loads((ROOT/f'build/{stem}-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/f'build/{stem}-result.json').write_text(json.dumps(r,indent=2)+'\n')
