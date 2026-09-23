"""Unicode17 default word-boundary conformance: not Intl lexical segmentation."""
import argparse,json,subprocess,time,zipfile,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
archive=ROOT/'build/UCD-17.zip';assert hashlib.sha256(archive.read_bytes()).hexdigest()=='2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e'
cases=[];expected=[]
for line in zipfile.ZipFile(archive).read('auxiliary/WordBreakTest.txt').decode().splitlines():
 body=line.split('#')[0].strip()
 if not body:continue
 regions=[];part=''
 for value in body.split():
  if value=='÷':
   if part:regions.append(part);part=''
  elif value!='×':part+=chr(int(value,16))
 assert not part
 cases.append(''.join(regions));expected.append(regions)
conformance=len(cases)
cases+=['','你好世界','foo.bar','a_b','\u0301a','a\u200d👩',' \u0301 ']
expected += [[],list('你好世界'),['foo.bar'],['a_b'],['\u0301','a'],['a\u200d👩'],[' \u0301',' ']]
long_texts=['a'+'\u0301'*100000,'a:'+'\u0301'*100000+'b','a:'+'\u0301'*100000+'!','🇦'*50000,'👩'+'\u200d👩'*20000,'a'*100000]
counts=[1,1,3,25000,1,1]
def summary(text,count):
 value=2166136261
 for c in text:value=((value*16777619)&0xffffffff)^ord(c)
 return f'{count}:{len(text)}:{value}'
long_expected=[summary(text,count) for text,count in zip(long_texts,counts) for _ in range(2)]
for backend in a.backends:
 command=['bun','build/word-break.js'] if backend=='bun' else ['build/word-break','--threads',backend[-1]]
 for first in range(0,len(cases),64):
  raw=subprocess.check_output(command+[json.dumps(cases[first:first+64])],text=True,cwd=ROOT,timeout=30)
  actual=[json.loads(line) for line in raw.splitlines()]
  for i,(got,want) in enumerate(zip(actual,expected[first:first+64])):
   assert got==[want,want],(backend,first+i,repr(cases[first+i]),got,want)
  assert len(actual)==len(cases[first:first+64])
 start=time.monotonic();result=subprocess.run(command+['long'],text=True,capture_output=True,cwd=ROOT,timeout=60)
 assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
 assert result.stdout.splitlines()==long_expected,(backend,result.stdout,long_expected)
 print(f'{backend}: {conformance} official and 7 explicit cases pass both APIs; six long runs {time.monotonic()-start:.3f}s',flush=True)
