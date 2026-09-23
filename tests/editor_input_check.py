"""Replay source Editor keyboard/history/paste callbacks; word engine is explicit oracle data."""
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--width-reference',required=True);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
def key(text): return dict(op='input',text=text)
traces=[
 [dict(op='add',text=t) for t in ['first','second','third']]+[key(x) for x in ['\x1b[A','\x1b[A','\x1b[B','x','\x1b[A','\x1b[A','\x1b[B']],
 [dict(op='set',text='abc\\'),key('\r'),key('x'),key('\r')],
 [key('\x1b[200~hello\r\nworld\x1b[201~'),key('\x01'),key('X'),key('\x7f'),key('\x1f')],
 [key('\x1b[200~'+'a'*1001+'\x1b[201~'),key('\x7f'),key('\x1f')],
 [dict(op='set',text='one\nshort\nlongest line'),dict(op='render',width=10)]+[key(x) for x in ['\x1b[A','\x1b[A','\x1b[A','\x1b[B','\x1b[B','\x1b[5~','\x1b[6~']],
 [dict(op='disable',value=True),key('hi'),key('\r'),dict(op='disable',value=False),key('\r')],
 [dict(op='set',text='中😀中😀😀hello world'),dict(op='render',width=15)]+[dict(op='mouse',x=x,y=y,width=15) for y,x in [(0,0),(1,0),(1,2),(1,7),(2,0),(2,3),(2,8),(3,0),(3,5),(4,2)]],
 [dict(op='set',text='alpha\nbeta\ngamma'),dict(op='render',width=20)]+[dict(op='mouse',x=x,y=y,width=20) for y,x in [(1,0),(1,5),(2,2),(3,3),(4,1),(9,2)]],
]
r=random.Random(921731)
keys=['a',' ','😀','中','e\u0301','\x1b[D','\x1b[C','\x1b[A','\x1b[B','\x01','\x05','\x7f','\x1b[3~','\x17','\x1bd','\x0b','\x15','\x19','\x1by','\x1f','\n','\r','\x1b[1;5D','\x1b[1;5C']
for _ in range(80):
 ops=[]
 for _ in range(60):
  kind=r.randrange(12)
  if kind<8: ops.append(key(r.choice(keys)))
  elif kind==8: ops.append(dict(op='set',text=r.choice(['hello world','中文abc😀','one\ntwo','long long line and more',''])))
  elif kind==9: ops.append(dict(op='add',text=r.choice(['prior prompt','another\nentry','  ' ])))
  elif kind==10: ops.append(dict(op='render',width=r.choice([8,15,40,80])))
  else: ops.append(key('\x1b[200~'+r.choice(['pasted\ntext','x\tq','\x1b[106;5u','./file'])+'\x1b[201~'))
 traces.append(ops)
reference=json.loads(subprocess.check_output(['bun','tests/editor_input_reference.ts',str(ROOT.parent/'pi-mono'),a.width_reference],input=json.dumps(traces),text=True,cwd=ROOT))
for i,(ops,ref) in enumerate(zip(traces,reference)):
 case=dict(ops=ops,words=ref['words'])
 actual=json.loads(subprocess.check_output(command+[json.dumps([case])],text=True,cwd=ROOT))[0]
 for j,(got,wanted) in enumerate(zip(actual,ref['results'])): assert got==wanted,(i,j,ops[:j+1],got,wanted)
print(f'{len(traces)} Editor input traces / {sum(map(len,traces))} transitions and ordered callback traces match source')
