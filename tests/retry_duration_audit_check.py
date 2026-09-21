"""Audit actual timer allocation/retirement in the retry duration smoke fixture.

Requires freshly compiled build/retry-duration-smoke.{c,js}; test-only C
instrumentation observes production primitive counters without supplying behavior.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
prefix = ROOT / 'build/retry-duration-smoke'
source = (candidate / 'effs/timer.c').read_text()
emitted = prefix.with_suffix('.c').read_text()
assert emitted.count(source) == 1
assert source.count('  row->gen += 1;') == 1
instrumented = 'static unsigned long long duration_created;\n' + source.replace('  row->gen += 1;', '  duration_created++;\n  row->gen += 1;')
emitted = emitted.replace(source, instrumented) + r'''
static void __attribute__((destructor)) duration_audit(void) {
  u32 live=0, waiting=0, channels=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
  fprintf(stderr,"DURATION_AUDIT %llu %u %u %u\n",duration_created,live,waiting,channels);
}
'''
audit = Path(str(prefix) + '-audit')
audit.with_suffix('.c').write_text(emitted)
subprocess.run(['clang', '-std=c11', '-O1', '-fbracket-depth=2048', str(audit.with_suffix('.c')), '-lpthread', '-lm', '-o', str(audit)], check=True)
records = []
for threads in [1, 4]:
    result = subprocess.run([str(audit), '--threads', str(threads)], capture_output=True, text=True, check=True, timeout=10)
    assert result.stdout == 'PASS provider sleep\n', result
    # Exactly the two valid sleeps allocate timers. Pre-aborted valid sleep and
    # both invalid sleeps (bare/pre-aborted) must allocate none.
    assert result.stderr == 'DURATION_AUDIT 2 0 0 0\n', result
    records.append(dict(threads=threads, audit=result.stderr.strip()))
    print(threads, 'threads: duration allocation/cleanup PASS', flush=True)
pending = [ROOT/'packages/ai/test/provider-retry-sleep.bend']; seen = set()
while pending:
    path = pending.pop().resolve()
    if path in seen: continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
seen.add(Path(__file__).resolve())
(ROOT/'build/retry-duration-audit-result.json').write_text(json.dumps(dict(scope='Native timer allocation and final resource counters for valid, pre-aborted and invalid retry sleeps. Numeric conversion and generic no-effect/error laws validated separately.', sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)}, generated_sha256=hashlib.sha256(emitted.encode()).hexdigest(), timer_sha256=hashlib.sha256(source.encode()).hexdigest(), samples=records), indent=2)+'\n')
