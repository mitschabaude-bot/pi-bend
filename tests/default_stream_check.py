"""Default selection timing through public entries and full native loops."""
from upstream_pin import check_sibling
check_sibling()
import itertools
import json
import subprocess
from pathlib import Path
from schema_literals import string

ROOT = Path(__file__).resolve().parents[1]
dependency = ROOT / 'build/schema-reference/node_modules/typebox/package.json'
if not dependency.exists():
    subprocess.run(['npm', 'install', '--prefix', str(ROOT / 'build/schema-reference'),
                    '--ignore-scripts', '--no-audit', '--no-fund', 'typebox@1.3.27'], check=True)
cases = [dict(entry=entry, selection=selection, kind=kind, terminate=False,
              steering=False, follow=False, stop=False, failAt='')
         for entry, selection, kind in itertools.product([1, 2, 3, 4], range(8), [0, 4])]
for entry, selection, fail in itertools.product([1, 2], [2, 3, 4, 6],
                                              ['agent_start', 'turn_start', 'message_start:system', 'message_end:system',
                                               'message_start:prompt', 'message_end:prompt']):
    cases.append(dict(entry=entry, selection=selection, kind=4, terminate=False,
                      steering=False, follow=False, stop=False, failAt=fail))
expected = json.loads(subprocess.check_output(['node', 'tests/main_loop_reference.mts'],
                     input=json.dumps(cases), text=True, cwd=ROOT))
flag = lambda value: 'True{}' if value else 'False{}'
lines = ['import Base', 'import ../packages/agent/test/main-loop.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, (case, result) in enumerate(zip(cases, expected, strict=True)):
    args = [str(case['entry']), str(case['selection']), str(case['kind']), flag(case['terminate']), flag(case['steering']),
            flag(case['follow']), flag(case['stop']), string(case['failAt']),
            string(result['history']), string(result['error']), string(result['trace']),
            string(result['requests']), str(result['providers']), str(result['executions']),
            str(result['validations'])]
    lines.append(f'    IO.print("default stream case {index}")')
    lines.append('    T.scenarioSelection(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} default-provider source comparisons")')
source = ROOT / 'build/default-stream-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/default-stream-check'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    result = subprocess.run([str(output), '--threads', threads], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        print(result.stdout)
        result.check_returncode()
    print(result.stdout.splitlines()[-1])
