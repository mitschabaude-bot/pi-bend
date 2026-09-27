"""Compare provider picker search state, mouse responses and ANSI frames with pi."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def cases():
    sequences=[
        ['down']*12+['up']*12,
        ['OpenAI','left','left','delete','home','x','end','backspace','undo'],
        ['word one two','wordLeft','killWord','yank','wordRight','undo'],
        ['\x1b[200~Token\x1b[201~','home','delete','end','backspace'],
        ['日本語🙂e\u0301','left','backspace','right','delete'],
        ['Token',{'zone':'search','x':2},'x',{'zone':'list','x':3},'backspace'],
        ['down','down','account','backspace','backspace','backspace','backspace','backspace','backspace','backspace'],
        [{'focus':False},{'focus':True},'mini'],
    ]
    for width in (12,24,40,80,120):
        for steps in sequences:
            yield dict(width=width,mode='login',query='',empty=False,steps=steps)
    for mode in ('login','logout'):
        yield dict(width=40,mode=mode,query='',empty=True,steps=['down','none','backspace'])
        yield dict(width=40,mode=mode,query='Cloud',empty=False,steps=['left','backspace','undo'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'build/provider-selector-input')
    args=parser.parse_args()
    inputs=list(cases())
    reference=subprocess.run(['bun','tests/provider_selector_reference.mts'],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True)
    wanted=json.loads(reference.stdout)
    for threads in (1,4):
        for i,(case,expected) in enumerate(zip(inputs,wanted)):
            steps=['key|'+s if isinstance(s,str) else ('focus|'+str(int(s['focus'])) if 'focus' in s else 'mouse|'+s['zone']+'|'+str(s['x'])) for s in case['steps']]
            command=[str(args.binary.resolve()),'--threads',str(threads),'--',str(ROOT),str(case['width']),case['mode'],str(int(case['empty'])),case['query'],*steps]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True)
            actual=[json.loads(line) for line in result.stdout.splitlines()]
            if actual!=expected:
                for step,(got,want) in enumerate(zip(actual,expected)):
                    if got!=want:
                        raise AssertionError(f'native{threads} case{i} step{step} {case}\nactual={got!r}\nexpected={want!r}')
                raise AssertionError(f'case{i}: {len(actual)} snapshots, expected {len(expected)}')
        print(f'native{threads}: {len(inputs)} provider picker sequences match pi',flush=True)

if __name__=='__main__':main()
