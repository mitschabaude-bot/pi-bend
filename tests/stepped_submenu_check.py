"""Compare stepped submenu transitions, callback ordering and ANSI frames with pi."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def cases():
    sequences=[
        ['enter','enter','escape'],
        ['Alpha','enter','down','enter','escape'],
        ['Beta','enter','escape','enter','enter','enter','up','enter'],
        ['Charlie','enter','enter','escape','escape'],
        ['word one','wordLeft','killWord','yank','undo','home','delete','escape'],
        ['enter','down','escape','up','enter','enter','escape'],
    ]
    for width in (12,24,40,80,120):
        for loop in (False,True):
            for steps in sequences:
                yield dict(width=width,loop=loop,start=0,steps=steps)
    for loop in (False,True):
        yield dict(width=40,loop=loop,start=1,steps=['enter','escape','enter','enter'])
        yield dict(width=40,loop=loop,start=1,steps=['escape','Alpha','enter','enter'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'build/stepped-submenu')
    args=parser.parse_args()
    inputs=list(cases())
    reference=subprocess.run(['bun','tests/stepped_submenu_reference.mts'],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True)
    wanted=json.loads(reference.stdout)
    for threads in (1,4):
        for i,(case,expected) in enumerate(zip(inputs,wanted)):
            command=[str(args.binary.resolve()),'--threads',str(threads),'--',str(ROOT),str(case['width']),str(int(case['loop'])),str(case['start']),*case['steps']]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True)
            actual=[json.loads(line) for line in result.stdout.splitlines()]
            if actual!=expected:
                for step,(got,want) in enumerate(zip(actual,expected)):
                    if got!=want:
                        raise AssertionError(f'native{threads} case{i} step{step} {case}\nactual={got!r}\nexpected={want!r}')
                raise AssertionError(f'case{i}: {len(actual)} snapshots, expected {len(expected)}')
        print(f'native{threads}: {len(inputs)} stepped submenu sequences match pi',flush=True)

if __name__=='__main__':main()
