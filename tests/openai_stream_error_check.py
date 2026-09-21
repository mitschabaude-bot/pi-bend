"""SSE API diagnostic formatting against the installed SDK and pinned pi formatter."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--backends', nargs='+', choices=['bun', 'native-1', 'native-4'], default=['bun'])
a = p.parse_args()
values = [{'message': 'quota 😀', 'code': 'limit'}, {'message': ''}, {'message': None}, {'message': ['a', 2]}, {'message': {'nested': True}}, {'code': 'unknown'}, {}, [], 'plain', 17, True, {'message': 'x' * 4500}]
reference = json.loads(subprocess.check_output(['node', '--disable-warning=ExperimentalWarning', 'tests/openai_stream_error_reference.mts'], input=json.dumps(values), text=True, cwd=ROOT))
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT.parent/'pi-mono', text=True).strip()
assert commit == '46c9de402bddf46b03c3b9f46487b777aaa41861'
# Existing native HTTP error policy preserves present false/zero messages;
# SDK truthiness instead falls back to the complete object. This is explicit.
adapted = [({'message': False}, 'false'), ({'message': 0}, '0')]
runs = []
for backend in a.backends:
    prefix = ROOT/'build/openai-stream-error'
    command = ['bun', str(prefix)+'.js'] if backend == 'bun' else [str(prefix), '--threads', backend.split('-')[1]]
    for value, expected in list(zip(values, reference['messages'])) + adapted:
        run = subprocess.run(command+['api', json.dumps(value, ensure_ascii=False)], cwd=ROOT, capture_output=True, text=True, timeout=10, check=True)
        assert not run.stderr and json.loads(run.stdout) == expected, (backend, value, expected, run)
        runs.append(dict(backend=backend, input=value, message=expected, sdk_comparison=(value, expected) not in adapted))
    run = subprocess.run(command+['protocol'], cwd=ROOT, capture_output=True, text=True, timeout=10, check=True)
    paths = [json.loads(line) for line in run.stdout.splitlines()]
    assert not run.stderr and paths == ['Invalid Responses event at $: missing field', 'Invalid Responses event at $["a.b[\\"😀\\"]"][2]["0"]: expected string', 'Invalid Responses event at $[0]: invalid value; expected finite number'], paths
    runs.append(dict(backend=backend, protocol_messages=paths))
    print(backend, '14 API messages and 3 native protocol diagnostics PASS', flush=True)
pending = [ROOT/'tests/openai-stream-error.bend'];seen = set()
while pending:
    path = pending.pop().resolve()
    if path in seen: continue
    seen.add(path)
    pending.extend(path.parent/n for n in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
seen.update([Path(__file__).resolve(), ROOT/'tests/openai_stream_error_reference.mts', ROOT.parent/'pi-mono/packages/ai/src/utils/error-body.ts'])
sdk = Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
seen.update([sdk/'package.json', sdk/'core/error.js'])
h = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
record = dict(scope=__doc__, sdk_version=reference['version'], reference_commit=commit, runs=runs, sources={str(path):h(path) for path in sorted(seen)}, programs={str(path):h(path) for path in [Path(str(prefix)+suffix) for suffix in ['', '.c', '.js']] if path.exists()})
(ROOT/('build/openai-stream-error-'+','.join(a.backends)+'-results.json')).write_text(json.dumps(record, indent=2)+'\n')
