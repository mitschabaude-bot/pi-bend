"""Gregorian UTC conversion; literal protocol years, no host local timezone."""
import calendar,json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
cases=[]
for year in [0,1,4,99,100,400,1582,1600,1900,1970,2000,2024,2100,2400,9999]:
 for month in range(1,13):
  for day in [0,1,28,29,30,31,32]:cases.append([year,month,day,23,59,59,999])
rng=random.Random(719528)
for _ in range(3000):
 year=rng.randrange(10000);month=rng.randrange(1,13)
 cases.append([year,month,rng.randrange(1,calendar.monthrange(year,month)[1]+1),rng.randrange(24),rng.randrange(60),rng.randrange(60),rng.randrange(1000)])
cases += [[1970,1,1,0,0,0,0],[1969,12,31,23,59,59,999],[0,1,1,0,0,0,0]]
for index,values in [(0,[10000,4294967295]),(1,[0,13,4294967295]),(2,[0,32,4294967295]),(3,[24,4294967295]),(4,[60,4294967295]),(5,[60,4294967295]),(6,[1000,4294967295])]:
 for value in values:
  row=[2024,2,29,12,30,20,1];row[index]=value;cases.append(row)
def invalid(row):
 y,m,d,h,mi,s,ms=row
 if y>9999:return 'year'
 if not 1<=m<=12:return 'month'
 if not 1<=d<=calendar.monthrange(y,m)[1]:return 'day'
 if h>23 or mi>59 or s>59 or ms>999:return 'time'
 return None
valid=[row for row in cases if invalid(row) is None]
script="""
const fs=require('fs');const rows=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([y,m,d,h,mi,s,ms])=>{
 const pad=(v,n)=>String(v).padStart(n,'0');
 const text=`${pad(y,4)}-${pad(m,2)}-${pad(d,2)}T${pad(h,2)}:${pad(mi,2)}:${pad(s,2)}.${pad(ms,3)}Z`;
 const value=Date.parse(text);if(!Number.isFinite(value))throw Error(text);
 const bits=BigInt.asUintN(64,BigInt(value));return (bits>>32n)+':'+(bits&0xffffffffn);
})));
"""
converted=iter(json.loads(subprocess.check_output(['node','-e',script],input=json.dumps(valid),text=True,cwd=ROOT)))
expected=[invalid(row) or next(converted) for row in cases]
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/calendar.bend','build/calendar'],cwd=ROOT,check=True)
for threads in ['1','4']:
 for start in range(0,len(cases),32):
  args=[';'.join(map(str,row)) for row in cases[start:start+32]]
  p=subprocess.run([str(ROOT/'build/calendar'),'--threads',threads,*args],capture_output=True,text=True,check=True,timeout=10)
  assert p.stdout.splitlines()==expected[start:start+32],(threads,start,p.stdout,expected[start:start+32])
  assert not p.stderr,p.stderr
 print(threads,'threads:',len(cases),'calendar conversions/validation cases PASS')
