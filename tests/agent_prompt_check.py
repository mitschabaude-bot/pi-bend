#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
expected=json.loads(subprocess.check_output(['node','tests/agent_prompt_reference.mts'],cwd=root,text=True))
assert len(expected)==6
lines=['import Base','import ../packages/agent/test/agent-prompt.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for mode,value in enumerate(expected):lines.append(f'    T.scenario({mode}, {json.dumps(value)})')
lines+=['    T.wallClock()','    IO.print("PASS 6 source prompt overloads and live timestamp")']
(root/'build/agent-prompt-check.bend').write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh','build/agent-prompt-check.bend','build/agent-prompt-check'],cwd=root,check=True)
for threads in ['1','4']:subprocess.run(['build/agent-prompt-check','--threads',threads],cwd=root,check=True,timeout=40)
