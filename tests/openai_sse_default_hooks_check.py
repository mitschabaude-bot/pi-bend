"""Native SSE default diagnostics and callback retirement across repeated lifetimes."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/openai-sse-default-hooks'
source = Path(str(PREFIX) + '.c').read_text()
Path(str(PREFIX) + '-audit.c').write_text(source + r'''
static void __attribute__((destructor)) default_hooks_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u 0\n",channels,io_park.head!=NULL);
}
''')
Path(str(PREFIX) + '-audit.js').write_text(instrument(Path(str(PREFIX) + '.js').read_text()))
subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', str(PREFIX) + '-audit.c', '-lpthread', '-lm', '-o', str(PREFIX) + '-audit'], check=True)
cases = [('{broken', [': current', 'data: {broken']), ('héllo\n😀', ['data: héllo', 'data: 😀', 'quote: "\\\t']), ('', [])]
expected = ''.join('Could not parse message into JSON: ' + data + '\nFrom chunk: ' + json.dumps(raw, ensure_ascii=False, separators=(',', ':')) + '\n' for data, raw in cases) * 8
runs = []
for audited in [False, True]:
    program = str(PREFIX) + ('-audit' if audited else '')
    for backend, command in [('native-1', [program, '--threads', '1']), ('native-4', [program, '--threads', '4']), ('bun', [str(Path.home() / '.bun/bin/bun'), program + '.js'])]:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
        assert result.stdout == 'caller:live\n' * 8, (backend, audited, result.stdout)
        assert result.stderr == expected + ('AUDIT 0 0 0\n' if audited else ''), (backend, audited, result.stderr, expected)
        runs.append({'backend': backend, 'audited': audited, 'owner_lifetimes': 8, 'diagnostic_calls': 32, 'abort_calls': 16, 'stdout': result.stdout, 'stderr': result.stderr})
        print(backend, 'audit' if audited else 'plain', '8 default hook lifetimes PASS', flush=True)
pending = [ROOT / 'tests/openai-sse-default-hooks.bend']
seen = {Path(__file__).resolve(), ROOT / 'tests/channel_audit.py'}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
h = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = {'scope': __doc__, 'runs': runs, 'sources': {str(p): h(p) for p in sorted(seen)}, 'program_sha256': {str(p): h(p) for p in [Path(str(PREFIX) + suffix) for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']]}}
Path(str(PREFIX) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
