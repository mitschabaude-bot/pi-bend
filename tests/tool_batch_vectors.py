"""Compare policy helpers with executable expressions from pinned agent-loop.ts."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node','tests/tool_batch_reference.mjs'], cwd=ROOT, text=True))
def mode(value): return 'None{}' if value is None else 'Some{A.' + value.capitalize() + '{}}'
def flag(value): return 'True{}' if value else 'False{}'
def items(values): return ' <> '.join([*values,'Nil{}'])
lines=['import Base','import ../packages/agent/test/tool-batch-policy.bend as T','import ../packages/agent/src/types.bend as A','def main() -> IO(Unit):','  do IO<Unit>:']
for case in reference['modes']:
    tools=items('T.ToolSpec{' + json.dumps(tool['name']) + ', ' + mode(tool.get('executionMode')) + '}' for tool in case['tools'])
    names=items(json.dumps(name) for name in case['names'])
    lines.append('    T.mode(' + ', '.join([tools,names,mode(case['configured']),json.dumps(case['expected'])]) + ')')
for case in reference['terminations']:
    values=items('None{}' if value is None else 'Some{' + flag(value) + '}' for value in case['values'])
    lines.append('    T.termination(' + values + ', ' + flag(case['expected']) + ')')
lines.append('    T.liveState()')
lines.append(f'    IO.print("PASS {len(reference["modes"])} mode and {len(reference["terminations"])} termination cases")')
source=BUILD/'tool-batch-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-tool-batch-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'):
    subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
