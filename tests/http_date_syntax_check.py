"""Recognize HTTP's three date syntaxes without choosing date interpretation."""
import calendar,datetime,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
rng=random.Random(9110);cases=[]
for _ in range(500):
 y=rng.randrange(1,10000);m=rng.randrange(1,13);d=rng.randrange(1,calendar.monthrange(y,m)[1]+1)
 dt=datetime.datetime(y,m,d,rng.randrange(24),rng.randrange(60),rng.randrange(60));w=dt.isoweekday()
 short=calendar.day_abbr[w-1];long=calendar.day_name[w-1];mon=calendar.month_abbr[m]
 time=dt.strftime('%H:%M:%S');tail=f'{m}:{d}:{dt.hour}:{dt.minute}:{dt.second}'
 cases += [(f'{short}, {d:02} {mon} {y:04} {time} GMT',f'imf:{w}:{y}:{tail}'),
           (f'{long}, {d:02}-{mon}-{y%100:02} {time} GMT',f'850:{w}:{y%100}:{tail}'),
           (f'{short} {mon} {d:2} {time} {y:04}',f'asc:{w}:{y}:{tail}')]
text='Sun, 06 Nov 1994 08:49:37 GMT';expected='imf:7:1994:11:6:8:49:37'
cases += [(text,expected),('  '+text+'  ',expected),(text.replace(' ','  '),expected)]
for bad in ['',text+' junk',text.replace('Sun,','Sunday,'),text.replace('Sun,','Sun'),text.replace('Nov','Foo'),text.replace('06','6'),text.replace('1994','94'),text.replace('GMT','UTC'),text.replace('08:49:37','8:49:37'),text.replace('08:49:37','08:49'),text.replace('08:49:37','08:49:37.0'),text.replace('1994','19x4'),text.replace('06','-6')]:cases.append((bad,'unrecognized'))
# Syntax deliberately retains invalid calendar fields for the interpreter.
cases += [('Sun, 31 Feb 2024 25:61:60 GMT','imf:7:2024:2:31:25:61:60')]
if '--no-build' not in sys.argv:
 subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/http-date-syntax-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/http-date-syntax.bend','build/http-date-syntax'],cwd=ROOT,check=True)
for threads in ['1','4']:
 for start in range(0,len(cases),24):
  batch=cases[start:start+24]
  p=subprocess.run([str(ROOT/'build/http-date-syntax'),'--threads',threads,*[t for t,_ in batch]],capture_output=True,text=True,check=True,timeout=10)
  assert p.stdout.splitlines()==[e for _,e in batch],(threads,start,p.stdout,batch)
  assert not p.stderr,p.stderr
 print(threads,'threads:',len(cases),'HTTP date syntax cases PASS')
