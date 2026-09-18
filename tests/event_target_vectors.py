"""Compare actual native EventTarget dispatch with Node callback/error traces."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
reference = json.loads(subprocess.check_output(['node', 'tests/event_target_reference.mjs'], cwd=ROOT, text=True))
mode = {'noop': 'Noop', 'cancel': 'Cancel', 'stop': 'Stop', 'resetStop': 'ResetStop',
        'immediate': 'Immediate', 'throw': 'Throw', 'recursive': 'Recursive'}
def flag(value):
    return 'True{}' if value else 'False{}'
lines = ['import Base', 'import ../packages/runtime/test/event-target-state.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for fixture in reference['cases']:
    errors = ' <> '.join([*(json.dumps(value) for value in fixture['errors']), 'Nil{}'])
    args = [f'T.{mode[fixture["first"]]}{{}}', f'T.{mode[fixture["second"]]}{{}}',
            *(flag(fixture[key]) for key in ('passive', 'once', 'cancelable')),
            f'{fixture["repeat"]}n', json.dumps('|'.join(fixture['trace'])), errors]
    lines.append('    T.run(' + ', '.join(args) + ')')
lines.append('    T.sharedReports()')
lines.append(f'    IO.print("PASS {len(reference["cases"])} EventTarget callback, flag, recursion and queued-error traces")')
source = BUILD / 'event-target-vectors.bend'
source.write_text('\n'.join(lines) + '\n')
output = BUILD / 'test-event-target-vectors'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run([str(output), '--threads', threads], check=True, timeout=30)
print(f'PASS dispatcher reference {reference["node"]}; automatic next-tick delivery and promise listeners remain pending')
