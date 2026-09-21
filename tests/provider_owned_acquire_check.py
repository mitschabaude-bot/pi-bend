"""Effect ordering and affine channel-owner cleanup for lazy provider acquisition."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/provider-owned-acquire'
c = Path(str(PREFIX) + '.c').read_text()
Path(str(PREFIX) + '-audit.c').write_text(c + r'''
static void __attribute__((destructor)) acquire_owner_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u 0\n",channels,io_park.head!=NULL);
}
''')
Path(str(PREFIX) + '-audit.js').write_text(instrument(Path(str(PREFIX) + '.js').read_text()))
subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', str(PREFIX) + '-audit.c', '-lpthread', '-lm', '-o', str(PREFIX) + '-audit'], check=True)

cases = [(mode, payload) for payload in [0, 7, 0xffffffff] for mode in range(5)] * 4
expected = []
for mode, payload in cases:
    expected.append('prepare')
    if mode == 0:
        expected.append('request-error:payload fixture')
        continue
    expected.append('initialize')
    if mode == 1:
        expected.append('init-error:initialization fixture')
        continue
    expected.append(f'request:{payload}')
    if mode == 2:
        expected += ['runtime-close:11', 'request-error:request fixture']
        continue
    expected += ['acquired', 'response-close:22', 'runtime-close:11', 'release-error:close fixture' if mode == 4 else 'released']
arguments = [str(item) for pair in cases for item in pair]
runs = []
for audited in [False, True]:
    prefix = str(PREFIX) + ('-audit' if audited else '')
    for backend, command in [('native-1', [prefix, '--threads', '1']), ('native-4', [prefix, '--threads', '4']), ('bun', [str(Path.home() / '.bun/bin/bun'), prefix + '.js'])]:
        result = subprocess.run(command + arguments, cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
        assert result.stdout.splitlines() == expected, (backend, audited, result.stdout, expected)
        assert result.stderr == ('AUDIT 0 0 0\n' if audited else ''), result.stderr
        runs.append({'backend': backend, 'audited': audited, 'cases': len(cases), 'trace': result.stdout.splitlines()})
        print(backend, 'audit' if audited else 'plain', '60 acquisition paths PASS', flush=True)

pending = [ROOT / 'tests/provider-owned-acquire.bend']
seen = {Path(__file__).resolve(), ROOT / 'tests/channel_audit.py'}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
record = {'scope': __doc__, 'distinct_cases': 15, 'repetitions_per_process': 4, 'runs': runs, 'sources': {str(p): digest(p) for p in sorted(seen)}, 'program_sha256': {str(p): digest(p) for p in [Path(str(PREFIX) + suffix) for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']]}}
Path(str(PREFIX) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
