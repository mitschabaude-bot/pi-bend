"""Compare scoped picker search state, mouse responses and ANSI frames with pi."""
import argparse
import json
import re
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def cases():
    named=[
        ('marks every model after enabling all',['enableAll'],['zeta/last'],[True,True,True]),
        ('disables only the selected model after enabling all',['enableAll','enter'],['zeta/last'],[False,True,True]),
        ('enables only the selected model after clearing all',['clearAll','enter'],['zeta/last','alpha/a-long-model-name-with-dashes','alpha/other'],[True,False,False]),
        ('restores the all-enabled state after re-enabling the last disabled model',['enableAll','enter','down','down','enter'],['zeta/last'],[True,True,True]),
    ]
    for name,steps,enabled,expected in named:
        yield dict(name=name,width=120,count=3,enabled=enabled,empty=False,steps=steps,expected=expected)
    sequences=[
        ['down','down','enter','up','enter','save'],
        ['mini','left','left','delete','home','x','end','backspace','undo'],
        ['word one two','wordLeft','killWord','yank','wordRight','undo'],
        ['\x1b[200~mini\x1b[201~','backspace','ctrlC','down'],
        ['模型🙂e\u0301','left','backspace','right','delete'],
        ['mini',{'zone':'search','x':2},'x',{'zone':'list','x':3},'backspace'],
        ['down','provider','enableAll','clearAll','up','enter','save'],
        ['down','reorderUp','reorderDown','up','reorderDown','save'],
        ['enableAll'],
        ['enableAll','enter'],
        ['clearAll','enter'],
        ['enableAll','enter','enter'],
        ['down','down','refresh','refresh'],
        [{'focus':False},{'focus':True},'mini'],
    ]
    for width in (12,24,40,80,120):
        for steps in sequences:
            yield dict(width=width,enabled=None,empty=False,steps=steps)
    for enabled in ([],['alpha/mini','zeta/last'],['missing/model','alpha/other']):
        yield dict(width=40,enabled=enabled,empty=False,steps=['down','reorderUp','enter','mini','ctrlC','save'])
    yield dict(width=40,enabled=None,empty=True,steps=['down','save','escape'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'build/scoped-selector-input')
    args=parser.parse_args()
    inputs=list(cases())
    reference=subprocess.run(['bun','tests/scoped_selector_reference.mts'],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True)
    wanted=json.loads(reference.stdout)
    for threads in (1,4):
        for i,(case,expected) in enumerate(zip(inputs,wanted)):
            steps=['key|'+s if isinstance(s,str) else ('focus|'+str(int(s['focus'])) if 'focus' in s else 'mouse|'+s['zone']+'|'+str(s['x'])) for s in case['steps']]
            command=[str(args.binary.resolve()),'--threads',str(threads),'--',str(ROOT),str(case['width']),'all' if case['enabled'] is None else ','.join(case['enabled']),str(int(case['empty'])) if 'count' not in case else str(case['count']),*steps]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True)
            actual=[json.loads(line) for line in result.stdout.splitlines()]
            if 'expected' in case:
                ids=['zeta/last','alpha/a-long-model-name-with-dashes','alpha/other']
                final=actual[-1]
                enabled=[final['scope'] is None or model in final['scope'] for model in ids]
                rows=[re.sub(r'\x1b\[[0-9;]*m','',line) for line in final['lines']]
                markers=[any('✓ ' in row for row in rows if model.split('/')[1]+' [' in row) for model in ids]
                assert enabled==case['expected'] and markers==case['expected'], case['name']
                if all(case['expected']):assert any('all enabled' in row for row in rows),case['name']
            if actual!=expected:
                for step,(got,want) in enumerate(zip(actual,expected)):
                    if got!=want:
                        raise AssertionError(f'native{threads} case{i} step{step} {case}\nactual={got!r}\nexpected={want!r}')
                raise AssertionError(f'case{i}: {len(actual)} snapshots, expected {len(expected)}')
        print(f'native{threads}: {len(inputs)} scoped picker sequences match pi',flush=True)

if __name__=='__main__':main()
