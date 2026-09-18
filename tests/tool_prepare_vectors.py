"""Compare original argument-adapter identity/mutation rules with native Bend."""
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
reference=json.loads(subprocess.check_output(['node','tests/tool_prepare_reference.mjs'],cwd=ROOT,text=True))
lines=['import Base','import ../packages/agent/test/tool-preparation.bend as T','def main() -> IO(Unit):','  do IO<Unit>:']
for case in reference['cases']:
    text='failure' if case['failed'] else '|'.join(['same' if case['same'] else 'replaced',*(case[key] for key in ('id','name','signature','namespace','args'))])
    text+='|calls:'+str(case['invocations'])+'|original:'+('fresh' if case['originalChanged'] else 'old')
    lines.append(f'    T.run({case["mode"]}, '+json.dumps(text)+')')
lines.append('    T.crossType()')
lines.append('    IO.print("PASS six upstream argument preparation identity/mutation/failure cases")')
source=BUILD/'tool-prepare-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-tool-prepare-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
