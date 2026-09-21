"""Concrete system initialization diagnostics across native and Bun backends."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--backend', choices=['all','bun','native'], default='all')
args = parser.parse_args()
expected = ['Invalid resolver random-index bound', 'Resolver entropy source returned invalid bytes', 'Could not obtain resolver entropy (code 5): unavailable', 'Could not obtain retry entropy (code 2): missing', 'Retry entropy source returned 7 bytes; expected 8', 'Could not open resolver configuration (code 2): missing resolver file', 'Resolver configuration exceeds its byte limit', 'Invalid resolver configuration', 'first; second; third', '']
prefix = ROOT/'build/openai-initialization-error'
commands = [('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4']),('bun',['bun',str(prefix)+'.js'])]
runs = []
for backend, command in commands:
    if args.backend != 'all' and not backend.startswith(args.backend): continue
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
    actual = [json.loads(line) for line in result.stdout.splitlines()]
    assert not result.stderr and actual == expected, (backend, result, expected)
    runs.append(dict(backend=backend, messages=actual))
    print(backend, len(actual), 'diagnostics PASS', flush=True)
pending = [ROOT/'tests/openai-initialization-error.bend']; seen = set()
while pending:
    path = pending.pop().resolve()
    if path in seen: continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
seen.update([Path(__file__).resolve()])
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = dict(scope=__doc__, sources={str(p):hash_file(p) for p in sorted(seen)}, runs=runs)
Path('build/openai-initialization-error-'+args.backend+'-results.json').write_text(json.dumps(record,indent=2)+'\n')
