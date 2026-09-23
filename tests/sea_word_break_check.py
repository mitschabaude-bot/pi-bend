"""Full pinned Southeast Asian prefix contract, independent source-trie expectations."""
import argparse,json,random,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
for language in ['khmer','lao','thai','burmese']:
 words=sorted({line.split('#')[0].strip() for line in (ROOT/('build/icu78-source/'+language+'dict.txt')).read_text(encoding='utf-8-sig').splitlines() if line.split('#')[0].strip()})
 trie={}
 for word in words:
  node=trie
  for c in word:node=node.setdefault(c,{})
  node['']=True
 random.seed(7803)
 lo,hi,letter={'khmer':(0x1780,0x17e0,'ក'),'lao':(0xe80,0xee0,'ກ'),'thai':(0xe00,0xe60,'ก'),'burmese':(0x1000,0x10a0,'က')}[language]
 cases=sorted({word[:i] for word in words for i in range(len(word)+1)})
 cases+= [word+letter for word in words]
 cases+= [''.join(random.choices([chr(cp) for cp in range(lo,hi)],k=random.randrange(1,32))) for _ in range(4096)]
 cases+= ['a','😀','ក'*100000,'\u200d','\u200c']
 expected=[]
 for text in cases:
  node=trie;length=0;lengths=[]
  for c in text:
   length+=1
   if c not in node:break
   node=node[c]
   if '' in node:
    lengths.append(length)
    if len(node)==1:break
  expected.append([length,list(reversed(lengths))])
 fixture=ROOT/('build/'+language+'-prefix-fixture.tsv');fixture.write_text('\n'.join(text+'\t'+json.dumps(want,separators=(',',':')) for text,want in zip(cases,expected)))
 for backend in a.backends:
  cmd=['bun','build/sea-word-break.js'] if backend=='bun' else ['build/sea-word-break','--threads',backend[-1]]
  start=time.monotonic();result=subprocess.run(cmd+[language,str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=120)
  assert result.returncode==0 and not result.stderr,(backend,result.returncode,result.stderr)
  assert result.stdout.strip()==str(len(cases)),(backend,result.stdout,len(cases))
  print(f'{backend}: {len(cases)} exact {language} prefix/candidate results pass ({time.monotonic()-start:.3f}s)',flush=True)
