"""Source-oracle navigation with injected segmentation; no production Intl dependency."""
import argparse, json, subprocess, itertools, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--upstream',type=Path,default=ROOT.parent/'pi-mono')
a=p.parse_args()
source=(a.upstream/'packages/tui/src/word-navigation.ts').read_text()
assert hashlib.sha256(source.encode()).hexdigest()=='b73e915a524926ac8881731e89026b0bc7b5b0bd465de67257af81a420465c7f'
source=source[source.index('const wordSegmenter'):].replace('getWordSegmenter()', 'new Intl.Segmenter("en",{granularity:"word"})')
utils=(a.upstream/'packages/tui/src/utils.ts').read_text()
assert hashlib.sha256(utils.encode()).hexdigest()=='8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3'
punctuation=next(line for line in utils.splitlines() if line.startswith('export const PUNCTUATION_REGEX'))
oracle=ROOT/'build/word-navigation-oracle.ts'
oracle.write_text(punctuation+'\nconst isWhitespaceChar=(s:string)=>/\\s/.test(s);\n'+source+'''
const rows=JSON.parse(process.argv[2]);
for(const [text,cursor,backward,parts,marker] of rows){
 const c=[...text].slice(0,Number(cursor)).join('').length;
 const result=(backward?findWordBackward:findWordForward)(text,c,{segment:()=>parts.map(([segment,isWordLike])=>({segment,isWordLike})),isAtomicSegment:s=>s===marker});
 console.log([...text.slice(0,result)].length);
}
''')
rows=[];corrected={}
def add(text,cursor,backward,parts,marker=''):
 rows.append([text,str(cursor),backward,parts,marker])
# ICU segmentation is fixture generation only, injected into the Bend API.
texts=['hello world','foo.bar','foo:bar','path/to/file','你好世界 test','  hello  ','foo...bar','hello',"אב'",'👩🏽‍💻 café a_b','ไทยภาษา မြန်မာ','\ufeff x\u2028z']
request=[]
for text in texts:
 for cursor in range(len(text)+1):
  for backward in [False,True]:request.append([text,cursor,backward])
segjs='const s=new Intl.Segmenter("en",{granularity:"word"});console.log(JSON.stringify(JSON.parse(process.argv[1]).map(([t,c,b])=>[...s.segment(b?[...t].slice(0,c).join(""):[...t].slice(c).join(""))].map(x=>[x.segment,!!x.isWordLike]))));'
segments=json.loads(subprocess.check_output(['bun','-e',segjs,json.dumps(request)],text=True))
for (text,cursor,backward),parts in zip(request,segments):add(text,cursor,backward,parts)
# Arbitrary injected segment shapes: lexical punctuation, whitespace and atomic priority.
units=[['ab',True],['..',False],[' ',False],['[paste #1 +5 lines]',True],['אב\'',True],['!ab',True],['a..',True],['😀',False]]
for sequence in itertools.product(units,repeat=3):
 text=''.join(x[0] for x in sequence)
 for backward in [False,True]:add(text,len(text) if backward else 0,backward,list(sequence),'[paste #1 +5 lines]')
expected=[]
for first in range(0,len(rows),64):
 expected += subprocess.check_output(['bun',str(oracle),json.dumps(rows[first:first+64])],text=True).splitlines()
# Approved progress correction only where upstream stalls on lexical punctuation.
punct=set('(){}[]<>.,;:\'"!?+-=*/\\|&%^$#@~`')
for i,([text,cursor,backward,parts,marker],want) in enumerate(zip(rows,expected)):
 cursor=int(cursor)
 ordered=parts[::-1] if backward else parts
 edge=cursor
 for segment,word in ordered:
  if segment==marker:break
  if any(char.isspace() or char=='\ufeff' for char in segment):
   edge += -len(segment) if backward else len(segment)
   continue
  if word and int(want)==edge:
   count=0
   for char in segment[::-1] if backward else segment:
    if char not in punct:break
    count+=1
   assert count>0,(rows[i],want)
   expected[i]=str(edge-count if backward else edge+count);corrected[i]=want
  break
for backward in [False,True]:
 rows.append(['abc','3' if backward else '0',backward,[['abc',True]],'[missing]']);expected.append('MissingWordEngine:Thai')
# Typed native validation of caller-provided coordinates and partitions.
for row,want in [(['abc','4',False,[], ''],'InvalidCursor'),(['abc','0',False,[['ab',True]],''],'InvalidSegments'),(['abc','0',False,[['',False],['abc',True]],''],'InvalidSegments'),(['abc','0',False,[['xyz',True]],''],'InvalidSegments')]:rows.append(row);expected.append(want)
for backend in a.backends:
 command=['bun','build/word-navigation.js'] if backend=='bun' else ['build/word-navigation','--threads',backend[-1]]
 for first in range(0,len(rows),64):
  actual=subprocess.check_output(command+[json.dumps(rows[first:first+64])],cwd=ROOT,text=True,timeout=30).splitlines()
  assert len(actual)==len(rows[first:first+64])
  for offset,(got,want) in enumerate(zip(actual,expected[first:first+64])):assert got==want,(backend,first+offset,rows[first+offset],got,want)
 print(f'{backend}: {len(rows)} navigation comparisons pass ({len(corrected)} approved punctuation progress corrections)',flush=True)
