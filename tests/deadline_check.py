"""Check owned deadline scope lifecycle with isolated timer effects."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
bun = Path.home() / '.bun/bin/bun'
fixture = root / 'packages/runtime/test/deadline.bend'
results = []
with tempfile.TemporaryDirectory(dir=root / 'build', prefix='deadline-') as directory:
    folder = Path(directory)
    for suffix in ('c', 'js'):
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',str(root/'build'/('deadline-'+suffix+'-build.json')),'--',str(bun), str(candidate / 'main.ts'), str(fixture), '-o', str(folder / ('run.' + suffix))], cwd=root, check=True)
    subprocess.run(['clang','-std=c11','-O1','-fbracket-depth=2048',str(folder/'run.c'),'-lpthread','-lm','-o',str(folder/'production')],check=True)
    for label,command in [('native-1',[str(folder/'production'),'--threads','1']),('native-4',[str(folder/'production'),'--threads','4']),('bun',[str(bun),str(folder/'run.js')])]:
        for mode in ['pre','all']:
            run=subprocess.run([*command,mode],capture_output=True,text=True,check=True,timeout=10)
            assert run.stdout=='PASS deadline\n' and not run.stderr,(label,mode,run)
            results.append(dict(backend=label,mode=mode,instrumented=False))
    c = folder / 'run.c'
    original = (candidate / 'effs/timer.c').read_text()
    assert original in c.read_text()
    instrumented = 'static unsigned long long audit_created, audit_closed, audit_live, audit_peak, audit_parked;\n' + original
    instrumented = instrumented.replace('  row->gen += 1;', '  audit_created++; audit_live++; if (audit_live > audit_peak) audit_peak = audit_live;\n  row->gen += 1;')
    instrumented = instrumented.replace('  row->state = 2;', '  audit_parked += row->waiter != NULL;\n  row->state = 2;')
    instrumented = instrumented.replace('  row->live = 0;', '  audit_closed++; audit_live--;\n  row->live = 0;')
    audit = r'''
static void __attribute__((destructor)) sleep_audit(void) {
  u32 live=0,waiting=0,channels=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
  fprintf(stderr,"DEADLINE_AUDIT %llu %llu %u %llu %llu %u %u\n",audit_created,audit_closed,live,audit_peak,audit_parked,waiting,channels);
}
'''
    c.write_text(c.read_text().replace(original, instrumented) + audit)
    js = folder / 'run.js'
    original_js = (candidate / 'effs/timer.js').read_text()
    assert original_js in js.read_text()
    instrumented_js = 'const timerAudit={created:0,closed:0,live:0,peak:0,parked:0,waiting:0};\n' + original_js
    instrumented_js = instrumented_js.replace('  const row = { deadline:', '  timerAudit.created++; timerAudit.live++; timerAudit.peak=Math.max(timerAudit.peak,timerAudit.live);\n  const row = { deadline:')
    instrumented_js = instrumented_js.replace('    io.waits.splice(index, 1);', '    timerAudit.parked++;\n    io.waits.splice(index, 1);')
    instrumented_js = instrumented_js.replace('  row.state = 3;', '  timerAudit.closed++; timerAudit.live--;\n  row.state = 3;')
    instrumented_js = instrumented_js.replace('  row.waiter = wait;', '  timerAudit.waiting++;\n  row.waiter = wait;').replace('row.waiter = null;', 'timerAudit.waiting--; row.waiter = null;')
    instrumented_js += "\nprocess.on('exit',()=>console.error('DEADLINE_AUDIT',timerAudit.created,timerAudit.closed,timerAudit.live,timerAudit.peak,timerAudit.parked,timerAudit.waiting,-1));\n"
    js.write_text(js.read_text().replace(original_js, instrumented_js))
    subprocess.run(['clang', '-std=c11', '-O1', '-fbracket-depth=2048', str(c),
                    '-lpthread', '-lm', '-o', str(folder / 'run')], check=True)
    for backend, command in [('native-1', [str(folder / 'run'), '--threads', '1']),
                             ('native-4', [str(folder / 'run'), '--threads', '4']),
                             ('bun', [str(bun), str(folder / 'run.js')])]:
        for mode in ['pre','all']:
          for repetition in range(4):
            start = time.monotonic()
            result = subprocess.run([*command,mode], capture_output=True, text=True, check=True, timeout=10)
            assert result.stdout == 'PASS deadline\n', result.stdout
            fields = result.stderr.split()
            assert fields[0] == 'DEADLINE_AUDIT' and len(fields) == 8, result.stderr
            created, closed, live, peak, parked, waiting, channels = map(int, fields[1:])
            assert created == closed == (0 if mode=='pre' else 194), result.stderr
            assert live == waiting == 0, result.stderr
            if mode=='all':assert peak>=64 and parked>=1,result.stderr
            assert channels == (0 if backend.startswith('native') else -1), result.stderr
            results.append(dict(backend=backend, mode=mode, instrumented=True, repetition=repetition,
                                seconds=time.monotonic()-start, created=created, closed=closed,
                                peak_live=peak, cancelled_parked=parked, live=live, waiting=waiting,
                                channels=channels if channels >= 0 else None))
        print(backend, 'PASS', flush=True)
sources = [fixture, root / 'packages/runtime/src/deadline.bend', root/'tests/deadline_check.py',
           candidate / 'base.bend', candidate / 'effs/timer.c', candidate / 'effs/timer.js']
(root / 'build/deadline-result.json').write_text(json.dumps(dict(
    scope='Pre-aborted parents allocate no timers. Early close, expiry, parent reuse, broadcast to 64 scopes, 64 parent/expiry races and 32 close/expiry races per full run. Six unmodified runs plus 24 instrumented runs. Native exit audit includes all channel rows; Bun audits timers only. Finite lifecycle checks, not a benchmark or exhaustive race proof.',
    sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, samples=results,
), indent=2) + '\n')
