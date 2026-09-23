"""Check pure Bend dictionary loading and all weighted prefix matches exactly."""
import argparse,importlib.util,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('cjk',ROOT/'scripts/generate-cjk-dictionary.py');G=importlib.util.module_from_spec(spec);spec.loader.exec_module(G)
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
words={}
for line in G.source().decode('utf-8-sig').splitlines():
 line=line.split('#')[0].strip()
 if line:
  word,cost=line.split();words[word]=int(cost)
cases=list(words)+['','𠀀','不存在的很长的随机复合字串','日本語を勉強しています']
fixture=ROOT/'build/cjk-dictionary-fixture.tsv'
rows=[]
for text in cases:
 expected=[[i,words[text[:i]]] for i in range(1,min(len(text),20)+1) if text[:i] in words]
 rows.append(text+'\t'+json.dumps(expected,separators=(',',':')))
fixture.write_text('\n'.join(rows))
for backend in a.backends:
 command=['bun','build/cjk-dictionary.js'] if backend=='bun' else ['build/cjk-dictionary','--threads',backend[-1]]
 start=time.monotonic();result=subprocess.run(command+[str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=120)
 assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
 assert result.stdout.strip()==str(len(cases)),(backend,result.stdout,len(cases))
 print(f'{backend}: {len(cases)} complete exact dictionary prefix comparisons pass ({time.monotonic()-start:.3f}s)',flush=True)
