"""Compare native AbortSignal dispatch with Node, including full receiver identity."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/abort_event_reference.mjs'], cwd=ROOT, text=True))
lines = ['import Base', 'import ../packages/runtime/test/abort-events.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for case in reference['cases']:
    flags = [('True{}' if case[key] else 'False{}') for key in ('once', 'passive')]
    errors = ' <> '.join([*(json.dumps(value) for value in case['errors']), 'Nil{}'])
    args = [str(case['mode']), *flags, json.dumps('|'.join(case['trace'])), errors]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append("    T.concurrent()")
lines.append(f'    IO.print("PASS {len(reference["cases"])} AbortSignal event traces")')
source = BUILD / 'abort-event-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-abort-event-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
print(f'PASS AbortSignal reference {reference["node"]}; next-tick delivery, dependent signals and complete API remain pending')
