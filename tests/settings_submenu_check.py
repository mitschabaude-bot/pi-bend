"""Compare settings submenu search state, selection actions and ANSI frames with pi."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def cases():
    sequences=[
        ['down','down','up','enter','escape'],
        ['Beta','left','left','delete','home','x','end','backspace','undo'],
        ['word one two','wordLeft','killWord','yank','wordRight','undo'],
        ['\x1b[200~high\x1b[201~','home','delete','end','backspace'],
        ['模型🙂e\u0301','left','backspace','right','delete'],
        ['up']*12+['backspace','enter'],
    ]
    for width in (12,24,40,80,120):
        for steps in sequences:
            yield dict(width=width,searchable=True,current='c',description='Step 1/2 · Select a model to configure',empty=False,steps=steps)
    for searchable in (False,True):
        yield dict(width=40,searchable=searchable,current='',description='',empty=False,steps=['b','down','up','enter','escape'])
        yield dict(width=40,searchable=searchable,current='',description='Empty',empty=True,steps=['down','up','enter','escape'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'build/settings-submenu')
    args=parser.parse_args()
    inputs=list(cases())
    reference=subprocess.run(['bun','tests/settings_submenu_reference.mts'],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True)
    wanted=json.loads(reference.stdout)
    for threads in (1,4):
        for i,(case,expected) in enumerate(zip(inputs,wanted)):
            command=[str(args.binary.resolve()),'--threads',str(threads),'--',str(ROOT),str(case['width']),str(int(case['empty'])),str(int(case['searchable'])),case['current'],case['description'],*case['steps']]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True)
            actual=[json.loads(line) for line in result.stdout.splitlines()]
            if actual!=expected:
                for step,(got,want) in enumerate(zip(actual,expected)):
                    if got!=want:
                        raise AssertionError(f'native{threads} case{i} step{step} {case}\nactual={got!r}\nexpected={want!r}')
                raise AssertionError(f'case{i}: {len(actual)} snapshots, expected {len(expected)}')
        print(f'native{threads}: {len(inputs)} settings submenu sequences match pi',flush=True)

if __name__=='__main__':main()
