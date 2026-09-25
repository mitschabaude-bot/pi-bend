"""All original named context-estimation cases and a native typed integration."""
from upstream_pin import UPSTREAM
import re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
source=UPSTREAM / 'packages/ai/test/context-estimate.test.ts'
native=ROOT/'packages/ai/test/context-estimate.bend'
names=re.findall(r'\bit\("([^"\n]+)"',source.read_text())
assert re.findall(r'IO.print\("PASS ([^"\n]+)"\)',native.read_text())==names
for fixture,output in [(native,BUILD/'test-context-estimate'),(ROOT/'packages/ai/test/api/typed-estimate.bend',BUILD/'test-typed-estimate')]:
    subprocess.run(['sh','scripts/build-pure.sh',str(fixture),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        result=subprocess.check_output([str(output),'--threads',threads],cwd=ROOT,text=True,timeout=120)
        if fixture==native:assert result.splitlines()==['PASS '+name for name in names],result
        print(result,end='')
