"""Replay pinned parser assertions and compare generated valid protocol inputs."""
import json, pathlib, random, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
ESC='\x1b'
rng=random.Random(771)
wrap=lambda text,end='\x07':ESC+']11;'+text+end
cases=['',wrap(''),wrap('not-a-color')]
for _ in range(700):
    widths=[rng.randrange(1,5) for _ in range(3)]
    channels=[f'{rng.randrange(16**w):0{w}x}' for w in widths]
    prefix=rng.choice(['rgb:','RGB:','rgba:','', 'RgB:'])
    value=prefix+'/'.join(channels)
    if prefix=='rgba:' and rng.randrange(2):value+='/ffff'
    cases.append(wrap(rng.choice(['',' ','\u2003'])+value+rng.choice(['','\t','\ufeff']),rng.choice(['\x07',ESC+'\\'])))
for _ in range(160):
    width=rng.choice([6,12])
    cases.append(wrap('#'+''.join(rng.choice('0123456789abcdefABCDEF') for _ in range(width))))
for _ in range(120):
    cases.append(''.join(ESC+'[?997;'+rng.choice('12')+'n' for _ in range(rng.randrange(1,15))))
for value in ['#fff','#gggggg','rgb:/f/f','rgb:x/f/f','rgb:f/f','rgb:f/f/f?']:
    cases.append(wrap(value))
for value in [wrap('#ffffff'),ESC+'[?997;1n']:
    cases.extend(['x'+value,value+'x',value[:-1],value+ESC])
reference=json.loads(subprocess.check_output(['node','tests/terminal_colors_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
assert len(reference['names'])==4,reference['names']
inputs=reference['observations']+cases
expected=reference['original']+reference['results']
# Deliberate strictness: no trailing garbage, overlong X11 channels or ignored
# extra/invalid alpha fields. Framing remains recognized for invalid colors.
corrections=[(wrap('rgb:fffff/0/0'),[True,None,None]),(wrap('rgb:f/f/f/junk'),[True,None,None]),(wrap('rgba:f/f/f/no'),[True,None,None]),(wrap('rgba:f/f/f/f/0'),[True,None,None]),(wrap('#ffffff')+'\n',[False,None,None]),(ESC+'[?997;1n\n',[False,None,None])]
long=[(wrap('x'*40000),[True,None,None]),((ESC+'[?997;2n')*2000,[False,None,'light'])]
commands={'bun':['bun','build/terminal-colors.js'],'native-1':['build/terminal-colors','--threads','1'],'native-4':['build/terminal-colors','--threads','4']}
for backend in sys.argv[1:] or commands:
    command=commands[backend]
    for start in range(0,len(inputs),80):
        run=subprocess.run(command+[json.dumps(inputs[start:start+80])],cwd=ROOT,capture_output=True,text=True,timeout=15,check=True)
        actual=[json.loads(line) for line in run.stdout.splitlines()]
        assert actual==expected[start:start+80],(backend,start,[(a,b,inputs[start+i]) for i,(a,b) in enumerate(zip(actual,expected[start:start+80])) if a!=b][:3])
    for text,wanted in corrections+long:
        actual=json.loads(subprocess.check_output(command+[json.dumps([text])],cwd=ROOT,text=True,timeout=15))
        assert actual==wanted,(backend,text[:100],actual,wanted)
    print(f'{backend}: {len(inputs)} source comparisons across 4 original parser tests, {len(corrections)} strictness corrections and {len(long)} long scans passed',flush=True)
