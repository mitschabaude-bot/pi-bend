"""Compare normal tool extraction and batch routing with upstream."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/tool_selection_reference.mjs'], cwd=ROOT, text=True))
sets = [[], [('a','Sequential')], [('b','Parallel'),('b','Sequential')], [('a','Parallel'),('b','Sequential')]]
lines = ['import Base', 'import ../packages/agent/test/tool-selection.bend as T', 'import ../packages/agent/test/tool-batch-policy.bend as B', 'import ../packages/agent/src/types.bend as Agent', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    tags = ' <> '.join([json.dumps(tag) for tag in reference['patterns'][case['pattern']]] + ['Nil{}'])
    specs = ' <> '.join(['B.ToolSpec{'+json.dumps(name)+', Some{Agent.'+mode+'{}}}' for name,mode in sets[case['tools']]] + ['Nil{}'])
    configured = ['None{}','Some{Agent.Parallel{}}','Some{Agent.Sequential{}}'][case['global']]
    args = [tags,specs,'False{}' if case['tools']==0 else 'True{}',configured,json.dumps(case['mode']),json.dumps(case['ids']+'|' if case['ids'] else '')]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream tool-call extraction/selection cases")')
source = BUILD / 'tool-selection-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-tool-selection-vectors'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
