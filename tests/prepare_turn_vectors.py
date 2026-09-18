"""Compare awaited prepare-next-turn callback and replacement with upstream."""
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
reference=json.loads(subprocess.check_output(['node','tests/prepare_turn_reference.mjs'],cwd=ROOT,text=True))
lines=['import Base','import ../packages/agent/test/prepare-turn.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for case in reference['cases']:
    lines.append('    T.run('+', '.join([str(case['mode']),json.dumps(case['rendered']),str(case['calls']),json.dumps(case['original'])])+')')
lines.append('    IO.print("PASS five awaited prepare-next-turn callback/update cases")')
source=BUILD/'prepare-turn-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-prepare-turn-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
