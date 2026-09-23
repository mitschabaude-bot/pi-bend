"""Rendered Editor lines, cursor bytes, padding and scroll borders against source."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--width-reference',required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
r=random.Random(51002);cases=[]
texts=['','hello world','中😀e\u0301 hello world','one\ntwo\nthree','\n'.join('line '+str(i) for i in range(30))]
for text in texts:
 lines=text.split('\n')
 for width in [4,7,10,20,40,80]:
  for padding in [0,1,2]:
   for focused in [False,True]:
    line=r.randrange(len(lines));col=r.choice([0,len(lines[line])])
    cases.append(dict(text=text,width=width,rows=r.choice([10,24,40]),padding=padding,focused=focused,line=line,col=col))
expected=json.loads(subprocess.check_output(['bun','tests/editor_component_reference.ts',str(ROOT.parent/'pi-mono'),a.width_reference],input=json.dumps(cases),text=True,cwd=ROOT))
for start in range(0,len(cases),30):
 actual=json.loads(subprocess.check_output(command+[json.dumps(cases[start:start+30])],text=True,cwd=ROOT))
 for i,(got,wanted) in enumerate(zip(actual,expected[start:start+30])): assert got==wanted,(start+i,cases[start+i],got,wanted)
print(f'{len(cases)} exact Editor render cases')
