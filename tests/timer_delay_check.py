"""Compare native delay conversion with Node's timer constructor/insertion."""
import json, math, random, struct, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(8074)
values=[0.,-0.,1.,-1.,.1,.9999999999999999,1.0000000000000002,1.9,2.9,2147483646.9,2147483647.,2147483647.0000002,2147483648.,math.inf,-math.inf,math.nan,5e-324,-5e-324]
values += [struct.unpack('>d',rng.randbytes(8))[0] for _ in range(600)]
values += [rng.random()*2147483647 for _ in range(300)]
cases=[';'.join(map(str,struct.unpack('>II',struct.pack('>d',v)))) for v in values]
script="""
const fs=require('fs');const source=process.binding('natives')['internal/timers'];
if(!source.includes('msecs = MathTrunc(msecs);'))throw Error('review changed timer insertion');
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(cases.map(c=>{const [hi,lo]=c.split(';').map(Number);const b=Buffer.alloc(8);b.writeUInt32BE(hi);b.writeUInt32BE(lo,4);const t=setTimeout(()=>{},Math.max(0,b.readDoubleBE()));const n=Math.trunc(t._idleTimeout);clearTimeout(t);return String(n);})))
"""
expected=json.loads(subprocess.check_output(['node','--no-warnings','-e',script],input=json.dumps(cases),cwd=ROOT,text=True))
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/timer-delay.bend','build/timer-delay'],cwd=ROOT,check=True)
for threads in ['1','4']:
 for start in range(0,len(cases),32):
  result=subprocess.run([str(ROOT/'build/timer-delay'),'--threads',threads,*cases[start:start+32]],text=True,capture_output=True,check=True,timeout=10)
  assert result.stdout.splitlines()==expected[start:start+32],(threads,start,result.stdout,expected[start:start+32])
  assert not result.stderr,result.stderr
 print(threads,'threads:',len(cases),'timer delay conversions PASS')
