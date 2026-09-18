"""Compare next-turn replacement with the actual upstream runLoop block."""
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
reference=json.loads(subprocess.check_output(['node','tests/turn_update_reference.mjs'],cwd=ROOT,text=True))
levels={'minimal':'Minimal','low':'Low','medium':'Medium','high':'High','xhigh':'XHigh','max':'Max'}
def previous(value): return 'None{}' if value is None else 'Some{Ai.'+levels[value]+'{}}'
def requested(value):
    if value is None: return 'None{}'
    if value=='off': return 'Some{Ai.Off{}}'
    return 'Some{Ai.Thinking{Ai.'+levels[value]+'{}}}'
lines=['import Base','import ../packages/agent/test/turn-update.bend as T','import ../packages/ai/src/types.bend as Ai','def main() -> IO(Unit):','  do IO<Unit>:']
for case in reference['cases']:
    expected='|'.join([case['reasoning'] or 'none',str(case['sameModel']).lower()])
    lines.append('    T.run('+', '.join([previous(case['previous']),requested(case['requested']),str(case['mask']),'True{}' if case['present'] else 'False{}',json.dumps(expected)])+')')
lines.append(f'    IO.print("PASS {len(reference["cases"])} upstream next-turn update cases")')
source=BUILD/'turn-update-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-turn-update-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
