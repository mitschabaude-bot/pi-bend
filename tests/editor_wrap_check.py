"""Pinned source wrapping oracle, including registered atomic paste markers."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--width-reference',required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
assert command
texts=['','hello world','a  b   c','longunbreakablewordwithoutspaces','中文测试世界','a 😀 b 👨‍👩‍👧‍👦 end','e\u0301 a\u0308 b','one\ttwo','hello [paste #1 +20 lines] world','[paste #1 1001 chars][paste #2 +12 lines]','[paste #1] [paste #01] [paste #3 +0 lines]','[paste #1x] [paste #-1] [paste #2 + lines]','เ กำ ກຳ','a\u00a0b\u2003c']
cases=[dict(text=t,width=w,ids=ids) for t in texts for w in [0,2,3,5,8,12,20,40] for ids in [[],[1],[1,2,3]] if "\t" not in t or w == 0 or w >= 4]
r=random.Random(13827)
for _ in range(500):
 cases.append(dict(text=''.join(r.choice(['a',' ', '   ','中','😀','e\u0301','[paste #1 +20 lines]','[paste #7]']) for _ in range(r.randrange(1,30))),width=r.randrange(2,40),ids=[1,7]))
expected=json.loads(subprocess.check_output(['bun','tests/editor_wrap_reference.ts',str(ROOT.parent/'pi-mono'),a.width_reference],input=json.dumps(cases),text=True,cwd=ROOT))
for start in range(0,len(cases),50):
 actual=json.loads(subprocess.check_output(command+[json.dumps(cases[start:start+50],ensure_ascii=False)],text=True,cwd=ROOT))
 for i,(actual,wanted) in enumerate(zip(actual,expected[start:start+50])): assert actual==wanted,(start+i,cases[start+i],actual,wanted)
# Source recurses forever for one oversized indivisible grapheme. Keep it intact.
corrected=[dict(text=t,width=1,ids=[]) for t in ['中','😀','👨‍👩‍👧‍👦']]
actual=json.loads(subprocess.check_output(command+[json.dumps(corrected)],text=True,cwd=ROOT))
assert actual==[[dict(text=v['text'],startIndex=0,endIndex=len(v['text']))] for v in corrected]
print(f'{len(cases)} exact wrapping comparisons; 3 oversized-grapheme corrections')
