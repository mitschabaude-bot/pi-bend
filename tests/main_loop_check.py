"""Composed native main loop against pinned source, using real validators."""
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
cases = [dict(kind=kind, terminate=terminate, steering=steering, follow=follow,
              stop=stop, failAt='')
         for kind, terminate, steering, follow, stop in itertools.product(
             range(5), [False, True], [False, True], [False, True], [False, True])]
for kind in range(5):
    for fail in ['message_start:system', 'message_end:system',
                 'message_start:assistant:partial',
                 'message_end:assistant:' + ['tool', 'tool', 'error', 'aborted', 'done'][kind],
                 'tool_execution_start:call', 'tool_execution_end:call',
                 'message_start:tool:' + ('error' if kind == 1 else 'ok'),
                 'message_end:tool:' + ('error' if kind == 1 else 'ok'),
                 'turn_end', 'agent_end', 'turn_start', 'message_start:prepared', 'message_end:prepared']:
        cases.append(dict(kind=kind, terminate=False, steering=False, follow=False, stop=False, failAt=fail))
cases += [dict(kind=8, terminate=False, steering=steering, follow=follow, stop=False, failAt='') for steering, follow in itertools.product([False, True], repeat=2)]
expected = json.loads(subprocess.check_output(['node', 'tests/main_loop_reference.mts'],
                     input=json.dumps(cases), text=True, cwd=ROOT))
flag = lambda value: 'True{}' if value else 'False{}'
lines = ['import Base', 'import ../packages/agent/test/main-loop.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, (case, result) in enumerate(zip(cases, expected, strict=True)):
    args = [str(case['kind']), flag(case['terminate']), flag(case['steering']),
            flag(case['follow']), flag(case['stop']), string(case['failAt']),
            string(result['history']), string(result['error']), string(result['trace']),
            string(result['requests']), str(result['providers']), str(result['executions']),
            str(result['validations'])]
    lines.append(f'    IO.print("main loop case {index}")')
    lines.append('    T.scenario(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} complete internal-loop source comparisons")')
source = ROOT / 'build/main-loop-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/main-loop-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    result = subprocess.run([str(output), '--threads', threads], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        print(result.stdout)
        result.check_returncode()
    print(result.stdout.splitlines()[-1])
