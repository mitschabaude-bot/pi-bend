"""Pinned ICU78 CJK engine comparisons; not a complete Intl word segmenter."""
import argparse,importlib.util,json,random,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
G=module('cjk_data','scripts/generate-cjk-dictionary.py')
P=module('cjk_props','scripts/generate-cjk-properties.py')
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
words={}
for line in G.source().decode('utf-8-sig').splitlines():
 line=line.split('#')[0].strip()
 if line:
  word,cost=line.split();words[word]=int(cost)
props=P.properties();eligible=[word for word in words if all(props[ord(c)]&2 for c in word)]
random.seed(7803)
cases=['你好世界','中华人民共和国','東京大学','関西国際空港','コンピューターサイエンス','カタカナ','ｶﾞｯﾂﾎﾟｰｽﾞ','㍿','蘭盧老','𠀀你好𪚥','日本語を勉強しています','東京特許許可局','','人人人人','アイウエオカキクケコサシスセソタチツテトナニヌネノ']
cases += random.sample(eligible,1024)
cases += [''.join(random.choices(eligible,k=random.randrange(2,6))) for _ in range(1024)]
cases += ['カ'*n for n in range(1,45)]
cases += ['ｶﾞ'*n+'ガ' for n in range(1,32)]
cases += ['㌕','㌖','㍍','神社','トウキョウ','とうきょう','𰻞𰻞麺','兀嗀']
cases += ['日本語を勉強しています'*2000,'カ'*20000,'ｶﾞ'*10000,'𠀀'*10000,'蘭'*10000]
fixture=ROOT/'build/cjk-fixture.json';fixture.write_text(json.dumps(cases,ensure_ascii=False))
version=json.loads(subprocess.check_output(['node','-p','JSON.stringify({icu:process.versions.icu,unicode:process.versions.unicode})'],text=True))
assert version=={'icu':'78.3','unicode':'17.0'},version
oracle='const s=new Intl.Segmenter("en",{granularity:"word"});for(const t of JSON.parse(require("fs").readFileSync(process.argv[1]))){const offsets=new Map([[0,0]]);let cu=0,cp=0;for(const c of t){cu+=c.length;offsets.set(cu,++cp);}console.log(JSON.stringify([...s.segment(t)].map(x=>offsets.get(x.index+x.segment.length))));}'
expected=[json.loads(line) for line in subprocess.check_output(['node','-e',oracle,str(fixture)],text=True).splitlines()]
# Exact normalization-boundary predicate across the complete scalar domain.
subprocess.run(['cc','-shared','-fPIC','-I/usr/include/node','tests/icu78_nfkc_boundary_oracle.c','-o','build/icu78-boundary.node'],cwd=ROOT,check=True)
subprocess.run(['node','-e','require("fs").writeFileSync("build/icu78-nfkc-boundaries.bin",require("./build/icu78-boundary.node").boundaries())'],cwd=ROOT,check=True)
assert (ROOT/'build/icu78-nfkc-boundaries.bin').read_bytes()==bytes(v&1 for v in props)
for backend in a.backends:
 cmd=['bun','build/cjk-word-break.js'] if backend=='bun' else ['build/cjk-word-break','--threads',backend[-1]]
 start=time.monotonic();result=subprocess.run(cmd+[str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=120)
 assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
 actual=[json.loads(line) for line in result.stdout.splitlines()]
 assert len(actual)==len(expected),(backend,len(actual),len(expected))
 for i,(got,want) in enumerate(zip(actual,expected)):assert got==want,(backend,i,cases[i],got,want)
 print(f'{backend}: {len(cases)} exact ICU78.3 CJK boundary comparisons pass ({time.monotonic()-start:.3f}s)',flush=True)
print('NFKC boundary-before: entire Unicode domain matches ICU78.3')
