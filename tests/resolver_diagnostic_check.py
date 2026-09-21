"""Native resolver diagnostic formatting across emitted backends."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--backend', choices=['all','bun','native'], default='all')
args = parser.parse_args()
expected = ['Invalid resolver file read size', 'Could not open resolver configuration (code 2): missing', 'Could not read resolver configuration (code 5): failed', 'Invalid resolver configuration byte 256 at offset 42', 'Invalid resolver configuration UTF-8 sequence at offset 2 (byte 192)', 'Incomplete resolver configuration UTF-8 sequence at offset 3', 'Resolver configuration has no name servers', 'Resolver configuration exceeds the supported three name servers', 'Invalid resolver timeout in seconds: 0', 'Malformed resolver option "attempts:\\"bad\\nvalue"', 'Unknown resolver option "未知"', 'Could not read resolver environment variable "RES_OPTIONS" (code 5): denied', 'Resolver configuration exceeds its byte limit', 'Could not read resolver configuration (code 9): closed', 'Incomplete resolver configuration UTF-8 sequence at offset 7']
prefix = ROOT/'build/resolver-diagnostic'
commands = [('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4']),('bun',['bun',str(prefix)+'.js'])]
runs = []
for backend, command in commands:
    if args.backend != 'all' and not backend.startswith(args.backend): continue
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
    actual = [json.loads(line) for line in result.stdout.splitlines()]
    assert not result.stderr and actual == expected, (backend, result, expected)
    runs.append(dict(backend=backend, messages=actual))
    print(backend, len(actual), 'diagnostics PASS', flush=True)
pending = [ROOT/'tests/resolver-diagnostic.bend']; seen = set()
while pending:
    path = pending.pop().resolve()
    if path in seen: continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
seen.update([Path(__file__).resolve()])
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = dict(scope=__doc__, sources={str(p):hash_file(p) for p in sorted(seen)}, runs=runs)
Path('build/resolver-diagnostic-'+args.backend+'-results.json').write_text(json.dumps(record,indent=2)+'\n')
