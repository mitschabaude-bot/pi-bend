"""Stream wrappers retain event order, settle before consumption and close on errors."""
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
cases = [dict(entry=entry, selection=0, kind=kind, terminate=terminate,
              steering=steering, follow=follow, stop=stop, failAt='')
         for entry, kind, terminate, steering, follow, stop in itertools.product(
             [1, 2], range(5), [False, True], [False, True], [False, True], [False, True])]
cases += [dict(entry=entry, selection=selection, kind=kind, terminate=False,
               steering=False, follow=False, stop=False, failAt='')
          for entry, selection, kind in itertools.product([1, 2, 3, 4], [1, 2, 5, 7], [0, 4])]
cases += [dict(entry=entry, selection=selection, kind=kind, terminate=False,
               steering=False, follow=False, stop=False, failAt='')
          for entry, selection, kind in itertools.product([1, 2], [0, 1], [5, 6])]
# A native channel gate makes the provider wait until the wrapper has returned
# its run handle. A synchronous wrapper would deadlock these fixtures.
cases += [dict(entry=entry, selection=selection, kind=7, terminate=False,
               steering=False, follow=False, stop=False, failAt='')
          for entry, selection in itertools.product([1, 2], [0, 1])]
expected = json.loads(subprocess.check_output(['node', 'tests/main_loop_reference.mts'],
                     input=json.dumps(cases), text=True, cwd=ROOT))
flag = lambda value: 'True{}' if value else 'False{}'
lines = ['import Base', 'import ../packages/agent/test/main-loop.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for index, (case, result) in enumerate(zip(cases, expected, strict=True)):
    events = [event for event in result['trace'].split('|') if event.startswith(('agent_', 'turn_', 'message_', 'tool_execution_'))]
    callbacks = [event for event in result['trace'].split('|') if event and event not in events]
    args = ['True{}', str(case['entry']), str(case['selection']), str(case['kind']), flag(case['terminate']), flag(case['steering']),
            flag(case['follow']), flag(case['stop']), string(case['failAt']),
            string(result['history']), string(result['error']), string('|'.join(callbacks)),
            string(result['requests']), str(result['providers']), str(result['executions']),
            str(result['validations']), string('|'.join(events))]
    lines.append(f'    IO.print("stream wrapper case {index}")')
    lines.append('    T.scenarioRuntime(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} asynchronous wrapper comparisons and approved failure closures")')
source = ROOT / 'build/loop-stream-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/loop-stream-check'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    result = subprocess.run([str(output), '--threads', threads], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        print(result.stdout)
        result.check_returncode()
    print(result.stdout.splitlines()[-1])
