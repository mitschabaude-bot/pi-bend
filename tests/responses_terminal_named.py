"""Original terminal-event contracts through the public async processor.

The provider wrapper early-EOF case stays pending; all three it.each phase
rows are retained. Inventory changes require this native run to pass.
"""
import argparse,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--batch-size',type=int,default=4)
args=parser.parse_args()
if args.batch_size < 1:parser.error('--batch-size must be positive')
source=(ROOT.parent/'pi-mono/packages/ai/test/openai-responses-terminal-event.test.ts').read_text()
native=(ROOT/'packages/ai/test/openai-responses-terminal-event.bend').read_text()
names=re.findall(r'\bit\("([^"\n]+)"',source)
ported=re.findall(r'IO.print\("PASS ([^"\n]+)"\)',native)
assert len(names)==8
assert ported==[names[0],'tracks message phases $phases (all three rows)',*names[2:]]
for row in [
    '{ phases: ["commentary", "commentary"], expected: ["pending", "pending"] }',
    '{ phases: ["final_answer", "final_answer"], expected: ["stop", "stop"] }',
    '{ phases: ["commentary", "final_answer"], expected: ["pending", "stop"] }',
]:assert row in source
functions=['rejectsEarlyEof','tracksPhases','replacesProvisionalStop','completed','incomplete','filtered','unknownReason','failed']
for start in range(0,len(functions),args.batch_size):
    selected=functions[start:start+args.batch_size]
    path=ROOT/f'build/responses-terminal-named-{start}.bend'
    path.write_text('import Base\nimport ../packages/ai/test/openai-responses-terminal-event.bend as Check\ndef main() -> IO(Unit):\n  do IO<Unit>:\n'+''.join(f'    Check.{name}()\n' for name in selected))
    out=path.with_suffix('')
    subprocess.run(['sh','scripts/build-pure.sh',str(path),str(out)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        result=subprocess.check_output([str(out),'--threads',threads],cwd=ROOT,text=True,timeout=120)
        assert result.splitlines()==['PASS '+name for name in ported[start:start+args.batch_size]],result
        print(result,end='',flush=True)
print('PASS original Responses terminal contracts (10/11 instances; wrapper case pending)',flush=True)
