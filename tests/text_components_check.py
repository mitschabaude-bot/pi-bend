"""Pinned Text/TruncatedText source assertions, callbacks, caches and rendering."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('backends',nargs='*',default=['bun','native-1','native-4'])
p.add_argument('--prefix',type=Path,default=ROOT/'build/text-components')
p.add_argument('--reference',default='/home/agent/code/pi-mono')
a=p.parse_args();E='\x1b'
oracle=['bun','tests/text_components_reference.ts',a.reference,'build/text-reference/node_modules']
def run(command,values):
 r=subprocess.run(command+[json.dumps(values,ensure_ascii=False,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert r.returncode==0 and not r.stderr,(command,r.returncode,r.stderr[-3000:])
 return json.loads(r.stdout)
def batches(command,values):
 out=[]
 for i in range(0,len(values),30):out.extend(run(command,values[i:i+30]))
 return out
original=json.loads(subprocess.check_output(oracle+['--original'],cwd=ROOT,text=True))
rng=random.Random(313);cases=[]
samples=['',' ','\t','\ufeff','\u0085','hello world','a\tb','\ta','a\nb\n','\r\n','a\r\nb',E+'[31mred words'+E+'[39m','界界abc','👩\u200d💻 🇦🇧 word','e\u0301 e\u0301','a\u00a0b','a\t\u302eb']
for component in ['text','truncated']:
 for text in samples:
  for width in [0,1,2,5,10,20]:
   for x in [None,0,1,3]:
    item=dict(component=component,text=text,width=width,paddingY=rng.choice([None,0,1,2]))
    if item['paddingY'] is None:del item['paddingY']
    if x is not None:item['paddingX']=x
    if component=='text':item['background']=rng.choice(['none','red','counter'])
    cases.append(item)
cache=[
 dict(text='alpha beta\nlast',paddingX=1,paddingY=2,background='counter',steps=[{'op':'render','width':8},{'op':'render','width':8},{'op':'render','width':9},{'op':'invalidate'},{'op':'render','width':9},{'op':'text','text':'alpha beta\nlast'},{'op':'render','width':9},{'op':'background','kind':'red'},{'op':'render','width':9},{'op':'background','kind':'blue'},{'op':'render','width':9},{'op':'background','kind':'counter'},{'op':'render','width':9},{'op':'background','kind':'none'},{'op':'render','width':9}]),
 dict(text='',background='counter',steps=[{'op':'render','width':10},{'op':'render','width':10},{'op':'text','text':'x'},{'op':'render','width':10},{'op':'text','text':' \t\ufeff'},{'op':'render','width':10}]),
]
expected=batches(oracle,cases+cache)
# The approved scanner correction preserves payload tabs. Text's source uses
# a blind replacement, so these expectations are intentionally independent.
corrected=[]
for control in [E+']8;;https://example.test/a\tb\x07',E+']0;window\ttitle'+E+'\\',E+'_payload\tdata'+E+'\\']:
 corrected.append((dict(text=control+'label\ttext',paddingX=0,paddingY=0,width=12),{'renders':[[control+'label   text']],'calls':[]}))
for backend in a.backends:
 command=['bun',str(a.prefix)+'.js'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1]]
 got=batches(command,[o['input'] for o in original])
 for o,v in zip(original,got):assert v==o['expected'],(backend,o['name'],o['expected'],v)
 actual=batches(command,cases+cache)
 for c,w,v in zip(cases+cache,expected,actual):assert v==w,(backend,c,w,v)
 for c,w in corrected:assert run(command,[c])[0]==w,(backend,c,run(command,[c]))
 long=[dict(text='word '*10000,paddingX=0,paddingY=0,width=80),dict(text=' '*100000,background='counter',width=80),dict(component='truncated',text='界x'*20000,paddingX=1,paddingY=1,width=30)]
 # Keep shell arguments below the system per-argument limit.
 for c in long:assert run(command,[c])==run(oracle,[c]),(backend,'long component input')
 print(f'{backend}: {len(original)} original TruncatedText tests, {len(cases)} rendering comparisons, {len(cache)} cache/callback sequences, {len(corrected)} control-tab corrections and {len(long)} long cases passed',flush=True)
