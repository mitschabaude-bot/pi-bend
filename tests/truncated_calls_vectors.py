"""Compare token-limit tool failures with the upstream batch and helpers."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/truncated_calls_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/agent/test/truncated-calls.bend as T', 'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    texts = ' <> '.join([json.dumps(text) for text in case['texts']] + ['Nil{}'])
    args = [str(case['count']), str(case['mode']), str(case['failAt'] if case['failAt']>=0 else 4294967295), json.dumps(case['result']), json.dumps(case['trace']+'|' if case['trace'] else ''), texts, json.dumps(case['ids']+'|' if case['ids'] else ''), str(case['events'])]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream truncated-tool-call cases")')
source = BUILD / 'truncated-calls-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-truncated-calls-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
