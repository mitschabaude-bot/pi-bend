"""Next-turn preparation composed with actual tool declaration reconciliation."""
import itertools
import json
import subprocess
from pathlib import Path
from schema_literals import string

ROOT = Path(__file__).resolve().parents[1]
cases = [dict(initial=initial, mode=mode, retained=retained, queueMode=queue, failAt='')
         for initial, mode, retained, queue in itertools.product([False, True], range(3), [False, True], range(3))]
for failure in ['turn_start', 'start:prepared', 'end:prepared', 'start:intent:new,',
                'end:intent:new,', 'start:queued', 'end:queued']:
    cases.append(dict(initial=False, mode=1, retained=False, queueMode=1, failAt=failure))
for failure in ['start:system:old,', 'end:system:old,']:
    cases.append(dict(initial=True, mode=0, retained=False, queueMode=0, failAt=failure))
expected = json.loads(subprocess.check_output(['node', 'tests/turn_preparation_reference.mts'],
                     input=json.dumps(cases), text=True, cwd=ROOT))
def flag(value): return 'True{}' if value else 'False{}'
lines = ['import Base', 'import ../packages/agent/test/turn-preparation.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for case, result in zip(cases, expected, strict=True):
    assert result['error'] in ['', 'prepare failed', 'queue failed', 'delivery failed'], result
    args = [flag(case['initial']), str(case['mode']), flag(case['retained']), str(case['queueMode']),
            string(case['failAt']), string(result['messages']), string(result['error']),
            ''.join(string(event) + ' <> ' for event in result['events']) + 'Nil{}']
    lines.append('    T.scenario(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} upstream next-turn preparation and tool declaration comparisons")')
source = ROOT / 'build/turn-preparation-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/turn-preparation-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=60)
