"""Compare steering/follow-up polling with original source statements."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/queue_poll_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/agent/test/queue-poll.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    args = [str(case['route']), 'True{}' if case['populated'] else 'False{}', str(case['mode']), str(case['calls']), json.dumps(case['rendered'])]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream queue polling cases")')
source = BUILD / 'queue-poll-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-queue-poll-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
