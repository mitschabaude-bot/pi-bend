"""Compare model picker search state, mouse responses and ANSI frames with pi."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def cases():
    sequences=[
        ['down','down','up','save','escape'],
        ['mini','left','left','delete','home','x','end','backspace','undo'],
        ['default','backspace','backspace','save'],
        ['word one two','wordLeft','killWord','yank','wordRight','undo'],
        ['\x1b[200~mini\x1b[201~','home','delete','end','backspace'],
        ['模型🙂e\u0301','left','backspace','right','delete'],
        ['mini',{'zone':'search','x':2},'x',{'zone':'list','x':3},'backspace'],
        ['tab','down','tab','down','enter'],
        ['up']*12+['backspace','enter'],
    ]
    for width in (12,24,40,80,120):
        for steps in sequences:
            yield dict(width=width,current=7,default=1,scoped=[],query='',empty=False,steps=steps)
    for scope in ([11,7,1],[],[2]):
        yield dict(width=40,current=7,default=1,scoped=scope,query='mini',empty=False,
                   steps=['backspace','backspace','backspace','backspace','down','tab','default','save'])
    yield dict(width=40,current=-1,default=-1,scoped=[],query='',empty=True,steps=['down','save','escape'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'build/model-selector-input-frames')
    args=parser.parse_args()
    inputs=list(cases())
    reference=subprocess.run(['bun','tests/model_selector_reference.mts'],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True)
    wanted=json.loads(reference.stdout)
    for threads in (1,4):
        for i,(case,expected) in enumerate(zip(inputs,wanted)):
            steps=['key|'+s if isinstance(s,str) else 'mouse|'+s['zone']+'|'+str(s['x']) for s in case['steps']]
            command=[str(args.binary.resolve()),'--threads',str(threads),'--',str(ROOT),str(case['width']),str(case['current']),str(case['default']),','.join(map(str,case['scoped'])),case['query'],str(int(case['empty'])),*steps]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True)
            actual=[json.loads(line) for line in result.stdout.splitlines()]
            if actual!=expected:
                for step,(got,want) in enumerate(zip(actual,expected)):
                    if got!=want:
                        raise AssertionError(f'native{threads} case{i} step{step} {case}\nactual={got!r}\nexpected={want!r}')
                raise AssertionError(f'case{i}: {len(actual)} snapshots, expected {len(expected)}')
        print(f'native{threads}: {len(inputs)} model picker sequences match pi',flush=True)

if __name__=='__main__':main()
