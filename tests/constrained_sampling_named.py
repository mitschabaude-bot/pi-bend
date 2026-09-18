"""Named constrained-sampling cases ported so far; remaining names stay pending."""
import re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT.parent/'pi-mono/packages/ai/test/constrained-sampling.test.ts').read_text()
native=ROOT/'packages/ai/test/constrained-sampling.bend'
names=re.findall(r'\bit\("([^"\n]+)"',source)
ported=re.findall(r'IO.print\("PASS ([^"\n]+)"\)',native.read_text())
assert set(ported)=={'converts supported constraints and falls back when unsupported', 'derives strict provider schemas without changing tool definitions', 'falls back or rejects schemas that cannot be safely converted', 'keeps grammar input JSON deltas append-only'}
ported=[name for name in names if name in ported]
assert set(ported)<=set(names) and len(names)==6
output=ROOT/'build/test-constrained-sampling'
subprocess.run(['sh','scripts/build-pure.sh',str(native),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    result=subprocess.check_output([str(output),'--threads',threads],cwd=ROOT,text=True,timeout=120)
    assert result.splitlines()==['PASS '+name for name in ported],result
    print(result,end='')
print(f'Constrained-sampling suite: {len(ported)}/{len(names)} named cases ported')
