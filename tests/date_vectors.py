"""Exact signed epoch conversion and live wall-clock primitive on both backends."""
import json
import os
from pathlib import Path
from bend_toolchain import BEND
import random
import shutil
import subprocess
import time
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
BEND=BEND
rng=random.Random(0xDA7E)
values=[0,1,-1,999,-999,1000,-1000,2**32-1,2**32,-2**32,2**53-1,2**53,2**53+1,-2**53-1,2**63-1,-2**63,8640000000000000,-8640000000000000]
values += [rng.randrange(-2**63,2**63) for _ in range(128)]
reference=json.loads(subprocess.check_output(['node','-e',"const b=Buffer.alloc(8);console.log(JSON.stringify(JSON.parse(process.argv[1]).map(s=>{b.writeDoubleBE(Number(BigInt(s)));return b.toString('hex')})))",json.dumps([str(v) for v in values])],text=True))
def words(v):
    v &= (1<<64)-1
    return f'W.U64{{{v>>32}, {v & 0xffffffff}}}'
lines=['import Base','import ../packages/runtime/src/date.bend as D','import ../packages/runtime/src/f64.bend as F','import ../packages/runtime/src/u64.bend as W','def check(value: W.U64, expected: W.U64) -> IO(Unit):','  Bool.pick(IO(Unit), W.equal(F.toBits(D.fromMilliseconds(value)), expected), IO.pure(Unit, Unit{}), IO.die(Unit, 1, "signed millisecond conversion mismatch"))','def main() -> IO(Unit):','  do IO<Unit>:']
for value, bits in zip(values,reference,strict=True): lines.append(f'    check({words(value)}, {words(int(bits,16))})')
lines.append(f'    IO.print("PASS {len(values)} signed epoch conversion vectors")')
source=BUILD/'date-vectors.bend'
source.write_text('\n'.join(lines)+'\n')
output=BUILD/'test-date-vectors'
subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run([str(output),'--threads',threads],check=True,timeout=30)
live=BUILD/'test-date'
subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/date.bend',str(live)],cwd=ROOT,check=True)
js=BUILD/'test-date.js'
subprocess.run([BEND,'packages/runtime/test/date.bend','-o',str(js)],cwd=ROOT,check=True)
bun=shutil.which('bun') or str(Path.home()/'.bun/bin/bun')
for command in ([str(live),'--threads','1'],[str(live),'--threads','4'],[bun,str(js)]):
    before=time.time_ns()//1_000_000
    actual=int(subprocess.check_output(command,text=True,timeout=30).strip())
    after=time.time_ns()//1_000_000
    assert before <= actual <= after, (command,before,actual,after)
print('PASS native one/four-thread and JS-backend Unix wall-clock readings within host call bounds')
