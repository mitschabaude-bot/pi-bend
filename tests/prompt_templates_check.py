"""Original Pi prompt assertions plus direct differential and malformed-input checks."""
import argparse,json,random,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def wire(value):return ','.join(str(ord(c)) for c in value)
def command(case):
 kind,args=case['kind'],case['args']
 if kind=='parseCommandArgs':return 'p|'+wire(args[0])
 if kind=='substituteArgs':return '|'.join(['s',wire(args[0]),*[wire(x) for x in args[1]]])
 return '|'.join(['e',wire(args[0]),*[wire(s) for t in args[1] for s in (t['name'],t['content'])]])
def expected(case):
 value=case['expected']
 return 'ok|'+(';'.join(map(wire,value)) if isinstance(value,list) else wire(value))
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');p.add_argument('--reference',type=Path,default=ROOT.parent/'pi-mono/packages/coding-agent');a=p.parse_args()
 cmd=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 rng=random.Random(809);cases=[]
 placeholders=['$1','$2','$0','$0001','$12','$@','$ARGUMENTS','${1:-fallback}','${2:-$1 $@}','${ARGUMENTS:-$2}','${@:-}','${@:0}','${@:2}','${@:1:0}','${@:1:3}','${@:99:1}','${1}','${@:-$ARGUMENTS}','$$1','\\$1','${wat$1}','${1:-unclosed $1','$arguments','$ARGUMENTSsuffix','${@:+1}','${@:2:-1}','${01:-z}','$'+'9'*500,'${@:'+('9'*500)+':1}']
 values=['','a','é 🎉','$1 $ARGUMENTS ${@:2}','\nline\tend','  spaces  ','日本語']
 for _ in range(400):cases.append(dict(kind='substituteArgs',args=['prefix '+''.join(rng.choices(placeholders,k=rng.randrange(1,7)))+' suffix',rng.choices(values,k=rng.randrange(7))]))
 spaces=[' ','\t','\r','\n','\u00a0','\u1680','\u2000','\u2028','\u2029','\u202f','\u205f','\u3000','\ufeff']
 for space in spaces:
  for quote in ['"',"'"]:
   cases.append(dict(kind='parseCommandArgs',args=[space+'one'+space+quote+'two'+space+'three'+quote+space+quote+quote+' tail']))
 templates=[dict(name='test',content='$1|$@|${2:-fallback}'),dict(name='test',content='must not select second'),dict(name='é',content='${@:2}')]
 for text in ['/test','/test\nfirst second','/test   \n x y',' /test x','/unknown "unfinished','/testx','/','/ test','/é a b','plain /test']:
  cases.append(dict(kind='expandPromptTemplate',args=[text,templates]))
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'cases.json';path.write_text(json.dumps(cases))
  reference=json.loads(subprocess.check_output(['bun',str(ROOT/'tests/prompt_templates_reference.ts'),str(a.reference),str(path)],text=True))
 for start in range(0,len(reference),35):
  batch=reference[start:start+35];r=subprocess.run([*cmd,'--',*[command(c) for c in batch]],capture_output=True,text=True,timeout=60)
  want=[expected(c) for c in batch]
  assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
  assert r.stdout.splitlines()==want,[(c,g,w) for c,g,w in zip(batch,r.stdout.splitlines(),want) if g!=w][:3]
 malformed=['"unfinished',"'unfinished",'a "b','"a"\'b']
 commands=['p|'+wire(x) for x in malformed]+['e|'+wire('/test '+x)+'|'+wire('test')+'|'+wire('$@') for x in malformed]
 result=subprocess.check_output([*cmd,'--',*commands],text=True).splitlines();assert result==['error']*len(commands),result
 assert subprocess.check_output([*cmd,'--','long'],text=True,timeout=60).strip()=='long-ok'
 print(f'{len(reference)} pinned public-call comparisons ({sum(c['origin']=='original' for c in reference)} from original assertions), {len(commands)} unclosed-quote rejections, 200KB replacement and unfinished-default scans passed')
if __name__=='__main__':main()
