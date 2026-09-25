"""Actual upstream runLoop decisions composed with native batch execution."""
import itertools
import json
import subprocess
from pathlib import Path
from schema_literals import string

ROOT = Path(__file__).resolve().parents[1]
cases = [dict(tools=tools, terminate=terminate, finishMode=finish, steeringMode=steering,
              followMode=follow, failAt='')
         for (tools, terminate), finish, steering, follow in itertools.product(
             [(False, False), (True, False), (True, True)], range(3), range(3), range(3))]
for tools, terminate, fail in [(False, False, 'turn_end'), (False, False, 'agent_end'),
                              (True, False, 'end:call'), (True, False, 'turn_end'),
                              (True, True, 'turn_end'), (True, True, 'agent_end')]:
    cases.append(dict(tools=tools, terminate=terminate, finishMode=0,
                      steeringMode=0, followMode=0, failAt=fail))
expected = json.loads(subprocess.check_output(['node', 'tests/turn_completion_reference.mjs'],
                     input=json.dumps(cases), text=True, cwd=ROOT))

def flag(value):
    return 'True{}' if value else 'False{}'

lines = ['import Base', 'import ../packages/agent/test/turn-completion.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for case, result in zip(cases, expected, strict=True):
    assert result['error'] in ['', 'delivery failed', 'finish failed', 'steering failed', 'follow failed'], result
    args = [flag(case['tools']), flag(case['terminate']), str(case['finishMode']), str(case['steeringMode']),
            str(case['followMode']), string(case['failAt']), str(result['category']),
            string(result['pending']), string(result['error']),
            ''.join(string(event) + ' <> ' for event in result['events']) + 'Nil{}']
    lines.append('    T.scenario(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} source runLoop turn-completion comparisons through native tool batches")')
source = ROOT / 'build/turn-completion-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/turn-completion-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=60)
