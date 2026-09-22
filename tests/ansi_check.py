"""Pinned ANSI oracle on supported escapes; explicit standards-based adaptations."""
import argparse
import json
from pathlib import Path
import random
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
ESC='\x1b'
def wire(s): return ','.join(str(ord(c)) for c in s)
def main():
    p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');a=p.parse_args()
    command=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
    rng=random.Random(853);cases=['','plain','a'+ESC+'[31mred'+ESC+'[0mz',ESC+'cdone']
    finals='ABCDEFGHIJKLMNOPRSTZcfghijklmnqrstuy=><~'
    for c in finals:cases.append('x'+ESC+c+'ok')
    for intro in [ESC+'[','\x9b']:
        for params in ['', '0','31','1;31','38;2;255;0;128','38:2::255:0:128','?25']:
            for end in 'mABCDHJKhl':cases.append('before'+intro+params+end+'after')
    for terminator in ['\x07',ESC+'\\','\x9c']:
        for payload in ['8;;https://example.com','0;title','new\nline','literal '+ESC+'[31m inside','🐍 café']:
            cases.append('a'+ESC+']'+payload+terminator+'z')
    for marker in [')B']:cases.append('x'+ESC+marker+'y')
    components=['plain','é🐍\n',ESC+'[31m',ESC+'[0m',ESC+']8;;url\x07',ESC+']8;;'+ESC+'\\','\x9b38:2::1:2:3m']
    cases += [''.join(rng.choices(components,k=rng.randrange(1,30))) for _ in range(700)]
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)/'cases.json';path.write_text(json.dumps(cases))
        expected=[json.loads(x) for x in subprocess.check_output(['bun',str(ROOT/'tests/ansi_reference.ts'),str(ROOT.parent/'pi-mono/packages/coding-agent/src'),str(path)],text=True).splitlines()]
    adaptations=[('x'+ESC+'(0y','xy'),('x'+ESC+'#8y','xy'),(ESC+']unterminated',ESC+']unterminated'),(ESC+']funterminated',ESC+']funterminated'),(ESC+'[123',ESC+'[123'),(ESC+'[123456789mX','X'),(ESC+'[38:2::255:0:0mX','X'),(ESC+'[ qX','X'),(ESC+'[999999999999uX','X'),('x'+ESC+'*0y','xy'),(ESC+'[31\ntext',ESC+'[31\ntext')]
    for c in range(64,127):adaptations.append(('a'+ESC+'[12;34'+chr(c)+'z','az'))
    preserved=['x'+ESC,'x'+ESC+'[','x'+ESC+'[12;','x'+ESC+']title',ESC+'[1 '+ '3x','\x90abc\x9c','\x9dabc\x9c',ESC+'\\ok',ESC+'^abc\x07',ESC+'_abc\x9c']
    adaptations += [(x,x) for x in preserved]
    cases += [x for x,_ in adaptations];expected += [y for _,y in adaptations]
    for start in range(0,len(cases),70):
        got=subprocess.run([*command,*map(wire,cases[start:start+70])],capture_output=True,text=True,timeout=30)
        assert got.returncode==0 and not got.stderr,(got.returncode,got.stderr)
        want=list(map(wire,expected[start:start+70]));actual=got.stdout.splitlines()
        assert actual==want,[(cases[start+i],actual[i],v) for i,v in enumerate(want) if i>=len(actual) or actual[i]!=v][:5]
    long=subprocess.run([*command,'long'],capture_output=True,text=True,timeout=30)
    assert long.returncode==0 and long.stdout=='long:ok\n' and not long.stderr,(long.returncode,long.stdout,long.stderr)
    print(f'{len(cases)-len(adaptations)} pinned comparisons, {len(adaptations)} explicit adaptations/preservation cases, four 200KB cases passed')
if __name__=='__main__':main()
