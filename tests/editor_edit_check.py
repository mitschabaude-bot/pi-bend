"""Exact pure-edit traces through the pinned Editor implementation."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--width-reference',required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
traces=[[{'op':'set','text':'hello\r\nworld\t!'}, {'op':'left'},{'op':'insert','text':'X\rY'},{'op':'undo'}], [{'op':'type','text':t} for t in ['a','b',' ','c','d',' ',' ']]+[{'op':'undo'}]*8, [{'op':'paste','text':'a'*1001},{'op':'undo'},{'op':'paste','text':'\n'.join(['line']*11)},{'op':'left'},{'op':'right'},{'op':'undo'}]]
r=random.Random(20318)
for _ in range(100):
 ops=[]
 for _ in range(80):
  op=r.choice(['set','type','type','insert','paste','left','right','home','end','backspace','delete','killStart','killEnd','yank','yankPop','undo'])
  text=r.choice(['abc','hello world','中😀','e\u0301','\r\n','\t']) if op!='type' else r.choice(['a','b',' ', '😀','中','e\u0301'])
  ops.append(dict(op=op,text=text))
 traces.append(ops)
expected=json.loads(subprocess.check_output(['bun','tests/editor_edit_reference.ts',str(ROOT.parent/'pi-mono'),a.width_reference],input=json.dumps(traces),text=True,cwd=ROOT))
for i,trace in enumerate(traces):
 actual=json.loads(subprocess.check_output(command+[json.dumps([trace])],text=True,cwd=ROOT))[0]
 for step,(got,wanted) in enumerate(zip(actual,expected[i])): assert got==wanted,(i,step,trace[:step+1],got,wanted)
print(f'{len(traces)} editor traces / {sum(map(len,traces))} transitions match pinned source')
