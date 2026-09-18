"""Run typed hook merges against the actual pinned upstream merge expression."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/tool_result_reference.mjs'], cwd=ROOT, text=True))
def flag(value): return 'True{}' if value else 'False{}'
lines = ['import Base','import ../packages/agent/test/tool-result-merge.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for case in reference['cases']:
    terminate = 'None{}' if case['expectedTerminate'] is None else 'Some{' + flag(case['expectedTerminate']) + '}'
    args = [*(str(case[key]) for key in ('content','details','flags','expectedDetails')), json.dumps(case['expectedContent']), flag(case['expectedUsage']), terminate, flag(case['expectedError'])]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream tool-result merge vectors and absent-result value checks")')
source = BUILD / 'tool-result-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-tool-result-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'):
    subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
