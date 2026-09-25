#!/usr/bin/env python3
"""Original named tests and actual-source manager differential checks."""
from upstream_pin import UPSTREAM
import argparse,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(command,inputs):
 p=subprocess.run(command+[json.dumps(inputs,separators=(',',':'))],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,(p.returncode,p.stderr[-3000:])
 return json.loads(p.stdout)
def raw(command,arg):
 return json.loads(subprocess.check_output(command+[arg],cwd=ROOT,text=True))
def batch(command,inputs):
 out=[]
 for i in range(0,len(inputs),8):out.extend(run(command,inputs[i:i+8]))
 return out
def queries(actions):
 return [{'method':m} for m in ['getConflicts','getUserBindings','getResolvedBindings']]+[{'method':m,'action':a} for a in actions for m in ['getKeys','getDefinition']]
def corpus(defs):
 rng=random.Random(481);out=[];names=list(defs);pool=['up','down','enter','ctrl+x','ctrl+j','shift+enter','ctrl+shift+up','alt+b','backspace','super+a']
 for i in range(150):
  definitions=defs if i%3==0 else {a:{'defaultKeys':rng.choices(pool,k=rng.randrange(5)),**({'description':a} if rng.randrange(2) else {})} for a in ['alpha','beta','gamma','delta']}
  actions=list(definitions)+['unknown'];selected=actions if i%3 else rng.sample(names,5)+['unknown'];steps=[]
  for j in range(4):
   config={a:(rng.choice(pool) if rng.randrange(2) else rng.choices(pool,k=rng.randrange(5))) for a in selected if rng.randrange(2)}
   steps.append({'replace':config,'queries':queries(actions)})
  out.append({'definitions':definitions,'bindings':{'unknown':['ctrl+x']},'steps':[{'queries':queries(actions)}]+steps})
 # Actual keyboard integration, including contexts that distinguish raw backspace.
 defs2={'letter':{'defaultKeys':['ctrl+h','alt+b','ctrl+space','shift+enter']},'back':{'defaultKeys':['backspace']},'ctrlback':{'defaultKeys':['ctrl+backspace']},'nav':{'defaultKeys':['left','up','ctrl+left']}}
 q=[]
 for kitty in [False,True]:
  for windows in [False,True]:
   for data in ['\x08','\x7f','\x00','\x1bb','\n','\r','\x1b[A','\x1b[1;5D','\x1b[13;2u','\x1b[127;5u','\x1b[104;5u','\x1b[27;5;104~']:
    q += [{'method':'matches','action':a,'data':data,'kitty':kitty,'windows':windows} for a in list(defs2)+['unknown']]
 out.append({'definitions':defs2,'steps':[{'queries':q}]})
 # Every actual default and description is observed, including unknown definitions.
 out.append({'steps':[{'queries':queries(names+['unknown'])}]})
 return out
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--reference',default=str(UPSTREAM));p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
 if command[:1]==['--']:command=command[1:]
 oracle=['bun','tests/keybindings_reference.ts',a.reference]
 originals=raw(oracle,'--original');actual=batch(command,[x['input'] for x in originals])
 assert len(actual)==len(originals)
 for source,got in zip(originals,actual):assert source['expected']==got,(source,got)
 print(f'{len(originals)} original assertions across {len(set(x["name"] for x in originals))} named tests passed',flush=True)
 inputs=corpus(raw(oracle,'--definitions'));expected=batch(oracle,inputs);actual=batch(command,inputs)
 assert len(actual)==len(expected)
 for i,(want,got) in enumerate(zip(expected,actual)):assert want==got,(i,inputs[i],want,got)
 count=sum(len(s['queries']) for c in inputs for s in c['steps'])
 print(f'{len(inputs)} managers / {count} source query comparisons passed',flush=True)
 # Native identity is semantic: modifier spelling and aliases cannot hide conflicts.
 case={'definitions':{'a':{'defaultKeys':['ctrl+shift+x','shift+ctrl+x','esc','escape']},'b':{'defaultKeys':[]}},'bindings':{'a':['ctrl+shift+x','shift+ctrl+x'],'b':['shift+ctrl+x'],'unknown':['ctrl+shift+x']},'steps':[{'queries':[{'method':'getKeys','action':'a'},{'method':'getConflicts'}]},{'replace':{},'queries':[{'method':'getKeys','action':'a'},{'method':'getConflicts'}]}]}
 expected=[[[['shift+ctrl+x'],[{'key':'shift+ctrl+x','keybindings':['a','b']}]],[[ 'shift+ctrl+x','escape'],[]]]]
 assert run(command,[case])==expected
 source=run(oracle,[case]);assert source!=expected,'Expected source spelling distinction not reproduced'
 print('Semantic deduplication/conflict correction and replacement passed',flush=True)
