"""Exact ICU78 word rules, mixed CJK dispatch, lexical statuses and missing engines."""
import argparse,importlib.util,itertools,json,random,struct,subprocess,time,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
version=json.loads(subprocess.check_output(['node','-p','JSON.stringify({icu:process.versions.icu,unicode:process.versions.unicode})'],text=True));assert version=={'icu':'78.3','unicode':'17.0'},version
cases=['ー'*12,'ｰ'*12,'ﾞ'*12,'ﾟ'*12,'','hello world','foo.bar','foo:bar','path/to/file','a_b','123abc','abc123','1カ2','_カナ123','你好world 123 foo.bar!','English日本語test','한국어test','א\'אב 1.5','カ\u0301ナ','中\u0301中','㌕世界','a\u200d👩🏽\u200d💻','🇦🇧🇨🇩🇪','\r\n',' \u0301 ','\ufeffx','᠀᠀','ภาษา','日本ภาษา','ພາສາ','မြန်မာ','ភាសា']
missing={27:'Thai',28:'Thai',29:'Lao',30:'Myanmar',31:'Khmer'}
units=['a','1','_',"'",'.',' ','\u0301','\u200d','中','カ','ー','😀']
cases += [''.join(parts) for parts in itertools.product(units,repeat=3)]
# Preserve the official Unicode corpus, but compare ICU's tailoring/statuses.
for line in zipfile.ZipFile(ROOT/'build/UCD-17.zip').read('auxiliary/WordBreakTest.txt').decode().splitlines():
 body=line.split('#')[0].strip()
 if body:cases.append(''.join(chr(int(v,16)) for v in body.split() if v not in ('÷','×')))
# Every compiled property-range boundary, including both ends, is classified.
b=(ROOT/'packages/runtime/data/icu78-word-rules.bin').read_bytes();states,classes,dict_start,count=struct.unpack_from('<4H',b,8);offset=16+states*(classes+3)
ranges=[struct.unpack_from('<IH',b,offset+6*i) for i in range(count)]
for i,(start,value) in enumerate(ranges):
 end=(ranges[i+1][0] if i+1<len(ranges) else 0x110000)-1
 for cp in {start,end}:
  if 0xd800<=cp<0xe000:continue
  char=chr(cp);cases.append(char)
  if value>>8 not in (3,4,5,6):cases.append('a'+char+'中');cases.append('1'+char+'カ')
random.seed(7803)
words=['hello','世界','東京大学','123','foo.bar','אב\'','日本語','カタカナ','ｶﾞｯﾂ','한국어','café','العربية','देवनागरी','_',':','?','\u0301','\u200d','😀',' ', '\r\n']
cases += [''.join(random.choices(words,k=random.randrange(2,10))) for _ in range(1024)]
cases += ['hello世界 123カタカナ. '*2000,'a'*100000,'ー'*20000,'_カ\u0301ナ'*4000,'a.'+'\u0301'*100000+'!']
fixture=ROOT/'build/word-segmenter-fixture.json';fixture.write_text(json.dumps(cases,ensure_ascii=False))
subprocess.run(['cc','-shared','-fPIC','-I/usr/include/node','tests/icu78_word_rules_oracle.c','-o','build/icu78-word-rules.node'],cwd=ROOT,check=True)
oracle=r'''
const fs=require('fs'),o=require('./build/icu78-word-rules.node'),s=new Intl.Segmenter('en',{granularity:'word'});
// Native Context eagerly owns CJK; warm ICU to the same explicit capability.
[...s.segment('日本')];
for(const text of JSON.parse(fs.readFileSync(process.argv[1]))){
 const bytes=Buffer.from(text),parts=[];let start=0;
 for(const [end,status] of o.segments(text)){parts.push([bytes.subarray(start,end).toString(),status>=100&&status<500,status]);start=end;}
 const intl=[...s.segment(text)].map(x=>[x.segment,!!x.isWordLike]);
 if(JSON.stringify(intl)!==JSON.stringify(parts.map(x=>x.slice(0,2))))throw Error('ICU/Intl disagreement');
 console.log(JSON.stringify(parts));
}
'''
expected=[json.loads(line) for line in subprocess.check_output(['node','-e',oracle,str(fixture)],cwd=ROOT,text=True,timeout=60).rstrip('\n').split('\n')]
for i,language in missing.items():expected[i]='MissingEngine:'+language
for backend in a.backends:
 cmd=['bun','build/word-segmenter.js'] if backend=='bun' else ['build/word-segmenter','--threads',backend[-1]]
 start=time.monotonic();result=subprocess.run(cmd+[str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=120)
 assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
 actual=[json.loads(line) for line in result.stdout.rstrip('\n').split('\n')];assert len(actual)==len(expected),(backend,len(actual),len(expected))
 for i,(got,want) in enumerate(zip(actual,expected)):assert got==want,(backend,i,repr(cases[i]),got,want)
 print(f'{backend}: {len(cases)} exact mixed-text/status results and typed missing-engine cases pass ({time.monotonic()-start:.3f}s)',flush=True)
