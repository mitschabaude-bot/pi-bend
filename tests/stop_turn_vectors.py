"""Check completed-turn hook, termination emission and queue ordering."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/stop_turn_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/agent/test/stop-turn.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    args = [str(case['mode']), json.dumps(case['result']), json.dumps(case['trace'] + '|'), 'True{}' if case['replaced'] else 'False{}']
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream completed-turn decision traces")')
source = BUILD / 'stop-turn-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-stop-turn-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
