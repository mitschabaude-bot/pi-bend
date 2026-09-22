"""Check pure Bend sleep composition with the isolated owned-timer compiler."""
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
bun = Path.home() / '.bun/bin/bun'
fixture = root / 'packages/runtime/test/abortable-sleep.bend'
results = []
with tempfile.TemporaryDirectory(dir=root / 'build', prefix='abortable-sleep-') as directory:
    folder = Path(directory)
    for suffix in ('c', 'js'):
        subprocess.run([str(bun), str(candidate / 'main.ts'), str(fixture), '-o',
                        str(folder / ('run.' + suffix))], cwd=root, check=True)
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
  fprintf(stderr,"SLEEP_AUDIT %llu %llu %u %llu %llu %u %u\n",audit_created,audit_closed,live,audit_peak,audit_parked,waiting,channels);
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
    instrumented_js += "\nprocess.on('exit',()=>console.error('SLEEP_AUDIT',timerAudit.created,timerAudit.closed,timerAudit.live,timerAudit.peak,timerAudit.parked,timerAudit.waiting,-1));\n"
    js.write_text(js.read_text().replace(original_js, instrumented_js))
    subprocess.run(['clang', '-std=c11', '-O1', '-fbracket-depth=2048', str(c),
                    '-lpthread', '-lm', '-o', str(folder / 'run')], check=True)
    for backend, command in [('native-1', [str(folder / 'run'), '--threads', '1']),
                             ('native-4', [str(folder / 'run'), '--threads', '4']),
                             ('bun', [str(bun), str(folder / 'run.js')])]:
        for repetition in range(8):
            start = time.monotonic()
            result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=10)
            assert result.stdout == 'PASS abortable sleep\n', result.stdout
            fields = result.stderr.split()
            assert fields[0] == 'SLEEP_AUDIT' and len(fields) == 8, result.stderr
            created, closed, live, peak, parked, waiting, channels = map(int, fields[1:])
            assert created == closed and created > 34, result.stderr
            assert live == waiting == 0 and peak >= 2 and parked >= 2, result.stderr
            assert channels == (0 if backend.startswith('native') else -1), result.stderr
            results.append(dict(backend=backend, repetition=repetition,
                                seconds=time.monotonic()-start, created=created, closed=closed,
                                peak_live=peak, cancelled_parked=parked, live=live, waiting=waiting,
                                channels=channels if channels >= 0 else None))
        print(backend, 'PASS', flush=True)
sources = [fixture, root / 'packages/runtime/src/socket.bend',
           candidate / 'base.bend', candidate / 'effs/timer.c', candidate / 'effs/timer.js']
(root / 'docs/bend-issues/2026-09-19-abortable-sleep-concurrency.json').write_text(json.dumps(dict(
    scope='Core cases plus eight broadcasts to 128 sleeps each, repeated abort/reason retention, independent signals and 90 deadline/abort races per process. Creation/cancellation timing may vary. Native exit audit includes all channel rows; Bun audits timers only. Instrumented finite checks, not a performance comparison or exhaustive race proof.',
    sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, samples=results,
), indent=2) + '\n')
