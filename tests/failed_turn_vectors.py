"""Compare failed/aborted turn completion with the original runLoop block."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/failed_turn_reference.mjs'], cwd=ROOT, text=True))
reasons = {'pending':'Pending','stop':'Stop','length':'Length','toolUse':'ToolUse','deferred':'Deferred','error':'Error','aborted':'Aborted'}
lines = ['import Base', 'import ../packages/agent/test/failed-turn.bend as T', 'import ../packages/ai/src/types.bend as Ai', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    args = ['Ai.'+reasons[case['reason']]+'{}', str(case['failAt'] if case['failAt']>=0 else 4294967295), 'True{}' if case['finishFails'] else 'False{}', json.dumps(case['result']), json.dumps(case['trace']+'|' if case['trace'] else ''), str(case['calls'])]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream assistant completion cases")')
source = BUILD / 'failed-turn-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-failed-turn-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
