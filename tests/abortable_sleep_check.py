"""Check pure Bend sleep composition with the isolated owned-timer compiler."""
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
fixture = root / 'packages/runtime/test/abortable-sleep.bend'
results = []
with tempfile.TemporaryDirectory(dir=root / 'build', prefix='abortable-sleep-') as directory:
    folder = Path(directory)
    for suffix in ('c', 'js'):
        subprocess.run([str(bun), str(candidate / 'main.ts'), str(fixture), '-o',
                        str(folder / ('run.' + suffix))], cwd=root, check=True)
    c = folder / 'run.c'
    c.write_text(c.read_text() + '''
static void __attribute__((destructor)) sleep_audit(void) {
  u32 live=0,waiting=0,channels=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
  fprintf(stderr,"SLEEP_AUDIT %u %u %u\\n",live,waiting,channels);
}
''')
    subprocess.run(['clang', '-std=c11', '-O1', '-fbracket-depth=2048', str(c),
                    '-lpthread', '-lm', '-o', str(folder / 'run')], check=True)
    for backend, command in [('native-1', [str(folder / 'run'), '--threads', '1']),
                             ('native-4', [str(folder / 'run'), '--threads', '4']),
                             ('bun', [str(bun), str(folder / 'run.js')])]:
        for repetition in range(8):
            start = time.monotonic()
            result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=10)
            assert result.stdout == 'PASS abortable sleep\n', result.stdout
            expected = 'SLEEP_AUDIT 0 0 0\n' if backend.startswith('native') else ''
            assert result.stderr == expected, result.stderr
            results.append(dict(backend=backend, repetition=repetition,
                                seconds=time.monotonic()-start, audit=result.stderr.strip()))
        print(backend, 'PASS', flush=True)
sources = [fixture, root / 'packages/runtime/src/abortable-sleep.bend',
           candidate / 'base.bend', candidate / 'effs/timer.c', candidate / 'effs/timer.js']
(root / 'docs/bend-issues/2026-09-19-abortable-sleep.json').write_text(json.dumps(dict(
    scope='32 normal waits on one reusable signal, zero delay, cancellation of long wait, pre-aborted signal, then signal disposal. Native exit audit checks timer rows, timer waiters and all channel rows. Finite composition tests, not provider retry parity.',
    sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, samples=results,
), indent=2) + '\n')
