"""Check awaited emission helpers against original source and explicit gates."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build'
BUILD.mkdir(exist_ok=True)
reference=json.loads(subprocess.check_output(['node','tests/tool_emit_reference.mjs'],cwd=ROOT,text=True))
lines=['import Base','import ../packages/agent/test/tool-emission.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for index, case in enumerate(reference['cases']):
    lines.append(f'    T.run({index}, ' + json.dumps('|'.join(case['trace'])) + ', ' + json.dumps(case['outcome']) + ')')
lines.append('    IO.print("PASS five upstream emission traces, awaited callbacks and shared payloads")')
source=BUILD/'tool-emit-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-tool-emit-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'):
    subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
