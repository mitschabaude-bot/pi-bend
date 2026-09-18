"""Source scheduler comparisons through the real native tool lifecycle."""
import itertools
import json
import subprocess
from pathlib import Path
from schema_literals import string

ROOT = Path(__file__).resolve().parents[1]
failures = ['', 'start:call', 'start:bad', 'start:missing', 'end:bad', 'end:missing',
            'update:call', 'end:call', 'message_start:call', 'message_end:call',
            'message_start:bad', 'message_end:bad', 'message_start:missing', 'message_end:missing']
cases = [dict(failAt=fail, initialAbort=initial, abortAfter=abort, blockBefore=block)
         for fail, initial, abort, block in itertools.product(failures, [False, True], [False, True], [False, True])]
expected = json.loads(subprocess.check_output(['node', 'tests/tool_batch_parallel_reference.mjs'],
                     input=json.dumps(cases), text=True, cwd=ROOT))

def boolean(value):
    return 'True{}' if value else 'False{}'

def values(items, show):
    return ''.join(show(item) + ' <> ' for item in items) + 'Nil{}'

lines = ['import Base', 'import ../packages/agent/test/tool-call-parallel.bend as T',
         'def main() -> IO(Unit):', '  do IO<Unit>:']
for case, result in zip(cases, expected, strict=True):
    if not result['ok']:
        assert result['error'] == 'delivery failed'
    args = [string(case['failAt']), boolean(case['initialAbort']), boolean(case['abortAfter']),
            boolean(case['blockBefore']), str(result['calls']), str(result['hooks']),
            values(result['events'], string), values([m['isError'] for m in result.get('messages', [])], boolean),
            boolean(result.get('terminate', False))]
    lines.append('    T.scenario(' + ', '.join(args) + ')')
lines.append(f'    IO.print("PASS {len(cases)} source parallel scheduling comparisons through native lifecycle")')
source = ROOT / 'build/tool-batch-parallel-check.bend'
source.write_text('\n'.join(lines) + '\n')
output = ROOT / 'build/tool-batch-parallel-check'
subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
for threads in ['1', '4']:
    subprocess.run([str(output), '--threads', threads], cwd=ROOT, check=True, timeout=60)
