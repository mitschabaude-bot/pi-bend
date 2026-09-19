"""Exact retry errors against pinned pi; binary64 ceil against native Math.ceil."""
import json, math, random, struct, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def words(value):return ';'.join(map(str,struct.unpack('>II',struct.pack('>d',value))))
rng=random.Random(9037)
values=[0.,-0.,1.,-1.,.1,-.1,.9999999999999999,-.9999999999999999,1.0000000000000002,-1.0000000000000002,2**52-0.5,2**52,2**53,math.inf,-math.inf,math.nan,5e-324,-5e-324]
values += [struct.unpack('>d',rng.randbytes(8))[0] for _ in range(600)]
cases=['c;'+words(v) for v in values]
for delay in [1.,1.0001,999.9,1000.,1000.00001,1001.,60001.,277403000.,1e20,1e24,1.7976931348623157e308,math.inf]:
 for limit in [5e-324,.1,1.,999.99,1000.,60000.]:
  if delay>limit:cases.append('d;'+words(delay)+';'+words(limit))
cases += ['a','o','p','r']
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/provider_retry_error_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
if '--no-build' not in sys.argv:
 subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/provider-retry-error-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/provider-retry-error.bend','build/provider-retry-error'],cwd=ROOT,check=True)
for threads in ['1','4']:
 for start in range(0,len(cases),24):
  result=subprocess.run([str(ROOT/'build/provider-retry-error'),'--threads',threads,*cases[start:start+24]],capture_output=True,text=True,check=True,timeout=30)
  actual=result.stdout.splitlines()
  # NaN payload/sign are immaterial; signed zero and every finite bit are checked.
  for offset,(got,want) in enumerate(zip(actual,expected[start:start+24])):
   if want=='nan':
    hi,lo=map(int,got.split(':'));assert math.isnan(struct.unpack('>d',struct.pack('>II',hi,lo))[0]),got
   else:assert got==want,(threads,cases[start+offset],got,want)
  assert len(actual)==len(expected[start:start+24]),result.stdout
  assert not result.stderr,result.stderr
 print(threads,'threads:',len(cases),'rounding/error comparisons PASS')
