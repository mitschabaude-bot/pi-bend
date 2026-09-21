"""Gated producer dependency retirement."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
BEND = ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts'
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = Path('tests/openai-session-cleanup.bend')
PREFIX = ROOT / 'build/openai-session-cleanup'
expected = 'PASS session cleanup ordering and single retirement\n'
pending, closure = [ROOT / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in closure:
        continue
    closure.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
sources = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(closure)}
runs = []
for backend in ['c', 'js']:
    with Path(str(PREFIX) + '-' + backend + '.log').open('w') as log:
        subprocess.run([str(BEND), str(SOURCE), '-o', str(PREFIX) + '.' + backend], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
Path(str(PREFIX) + '-audit.c').write_text(Path(str(PREFIX) + '.c').read_text() + r'''
static void __attribute__((destructor)) session_cleanup_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u\n",channels,io_park.head!=NULL);
}
''')
Path(str(PREFIX) + '-audit.js').write_text(instrument(Path(str(PREFIX) + '.js').read_text()))
for suffix in ['', '-audit']:
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', str(PREFIX)+suffix+'.c', '-lpthread', '-lm', '-o', str(PREFIX)+suffix], check=True, timeout=120)
    for name, command in [('native-1', [str(PREFIX)+suffix, '--threads', '1']), ('native-4', [str(PREFIX)+suffix, '--threads', '4']), ('bun', [BUN, str(PREFIX)+suffix+'.js'])]:
        run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=15, check=True)
        assert run.stdout == expected, (name, run)
        assert run.stderr == (('AUDIT 0 0 0\n' if name == 'bun' else 'AUDIT 0 0\n') if suffix else ''), (name, run)
        runs.append(dict(backend=name, audited=bool(suffix), passed=True))
        print(name, suffix or 'production', 'four cleanup outcomes PASS', flush=True)

assert sources == {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources}
record = dict(scope='Four typed outcomes, gated finalizer, result availability before cleanup, repeated wait/dispose, six backend/audit combinations. Finalizer runs once and is complete by wait; no HTTP or full-provider claim.', sources=sources, harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), programs={s:hashlib.sha256(Path(str(PREFIX)+s).read_bytes()).hexdigest() for s in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']}, runs=runs)
Path(str(PREFIX)+'-results.json').write_text(json.dumps(record, indent=2)+'\n')
