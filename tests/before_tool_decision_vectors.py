"""Compare post-validation before-hook decisions with the original block."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/before_tool_decision_reference.mjs'], cwd=ROOT, text=True))
def boolean(value): return 'True{}' if value else 'False{}'
def optional_bool(value): return 'None{}' if value is None else 'Some{'+boolean(value)+'}'
lines = ['import Base', 'import ../packages/agent/test/before-tool-decision.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    args=[boolean(case['aborted']),boolean(case['present']),optional_bool(case['block']),'None{}' if case['reason'] is None else 'Some{'+json.dumps(case['reason'])+'}',optional_bool(case['terminate']),json.dumps(case['rendered'])]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines += ['    T.live()', f'    IO.print("PASS {len(reference["cases"])} upstream before-tool decisions and live result mutation")']
source = BUILD / 'before-tool-decision-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-before-tool-decision-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
