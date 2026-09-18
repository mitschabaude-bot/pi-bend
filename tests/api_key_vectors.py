"""Compare awaited key resolution and post-callback fallback with upstream."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/api_key_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/agent/test/api-key.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    fallback = 'None{}' if case['fallback'] is None else 'Some{' + json.dumps(case['fallback']) + '}'
    retained = 'none' if case['retained'] is None else 'key:' + case['retained']
    args = [str(case['mode']), fallback, 'True{}' if case['rotate'] else 'False{}', 'True{}' if case['signaled'] else 'False{}', str(case['calls']), json.dumps(case['result']), json.dumps(retained)]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream API-key/request snapshot cases")')
source = BUILD / 'api-key-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-api-key-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
