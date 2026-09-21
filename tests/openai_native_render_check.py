"""Recursive native error rendering; reference retry text and typed leaf routing."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--backend', choices=['all','bun','native'], default='all')
args = parser.parse_args()
reference = json.loads(subprocess.check_output(['node','tests/openai_native_render_reference.mts'], cwd=ROOT, text=True))
expected = ['primary','formatting-failure','original','callback','reader','disposal','release',*(['formatting-failure']*3),'Request payload contains a non-finite number',reference['abort'],'Retry delay is outside the native timer range',reference['delay']]
prefix = ROOT/'build/openai-native-render'
commands = [('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4']),('bun',['bun',str(prefix)+'.js'])]
runs = []
for backend, command in commands:
    if args.backend != 'all' and not backend.startswith(args.backend): continue
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
    actual = [json.loads(line) for line in result.stdout.splitlines()]
    assert not result.stderr and actual == expected, (backend, result, expected)
    runs.append(dict(backend=backend, messages=actual))
    print(backend, len(actual), 'diagnostics PASS', flush=True)
pending = [ROOT/'tests/openai-native-render.bend']; seen = set()
while pending:
    path = pending.pop().resolve()
    if path in seen: continue
    seen.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
seen.update([Path(__file__).resolve(), ROOT/'tests/openai_native_render_reference.mts', ROOT.parent/'pi-mono/packages/ai/src/utils/provider-retry.ts'])
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = dict(scope=__doc__, sources={str(p):hash_file(p) for p in sorted(seen)}, runs=runs)
Path('build/openai-native-render-'+args.backend+'-results.json').write_text(json.dumps(record,indent=2)+'\n')
