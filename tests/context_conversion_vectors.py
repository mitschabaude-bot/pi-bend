"""Compare awaited context transformation and LLM conversion with upstream."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/context_conversion_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/agent/test/context-conversion.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    args = [str(case['mode']), 'True{}' if case['signaled'] else 'False{}', json.dumps(case['result']), json.dumps(case['trace'] + '|'), 'True{}' if case['replaced'] else 'False{}']
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream context conversion traces")')
source = BUILD / 'context-conversion-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-context-conversion-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
