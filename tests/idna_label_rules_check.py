"""Prepared-label syntax and status checks; full IDNA validation is separate."""
from itertools import product
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
def syntax(text,hyphens,std3):
    if hyphens:
        if text[2:4]=='--': return 'hyphen-positions'
        if text.startswith('-') or text.endswith('-'): return 'hyphen-edge'
    elif text.startswith('xn--'): return 'reserved'
    for char in text:
        if char=='.': return 'dot'
        if std3 and ord(char)<128 and not (char=='-' or 'a'<=char<='z' or '0'<=char<='9'):
            return 'ascii;'+str(ord(char))
    return 'ok'

def codes(text): return ','.join(map(str,map(ord,text)))
texts=['','a','-','a-','-a','ab--c','xn--','xn--é','XN--é','xN--é','a.b','\u3002','\x00','\x7f','\x80','a_b','é','🙂--a','🙂a--','🙂🙂--']
texts += [chr(code) for code in range(256)]
texts += [''.join(row) for n in range(5) for row in product('anx-.',repeat=n)]
rng=random.Random(461)
texts += [''.join(rng.choice('ab-xn._09AZé🙂') for _ in range(rng.randrange(100))) for _ in range(300)]
texts += ['a'*8192,'a'*8192+'-','a'*8192+'.','a'*8192+'_']
arguments=[]
expected=[]
for hyphens,std3 in product([False,True],repeat=2):
    for text in texts:
        arguments.append(f's;{int(hyphens)};{int(std3)};'+codes(text))
        expected.append(syntax(text,hyphens,std3))
for mode,status in product('nt','vdmix?'):
    arguments.append(f'v;{mode};{status}')
    expected.append(str(int(status=='v' or mode=='n' and status=='d')))
# The fixture's deliberately small table has real-shaped valid, mapped, ignored,
# deviation, disallowed and absent entries, including one multi-code-point range.
combined=['','a','z','A','ß','\u00ad','\u01f4','b?','aß','a\u00ad','aA','a.b','xn--a','ab--','-a','abc']
combined += [''.join(rng.choice('aAz-ß\u00ad\u01f4.?') for _ in range(rng.randrange(30))) for _ in range(100)]
for mode,hyphens,std3 in product('nt',[False,True],[False,True]):
    for text in combined:
        want=syntax(text,hyphens,std3)
        if want=='ok':
            for char in text:
                if char in '-.' or 'a'<=char<='z' or char=='ß' and mode=='n': continue
                want='status;'+str(ord(char))
                break
        arguments.append(f'c;{mode};{int(hyphens)};{int(std3)};'+codes(text))
        expected.append(want)
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-label-rules.bend','build/idna-label-rules'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-label-rules.bend','-o','build/idna-label-rules.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-label-rules','--threads','1']),('native 4',['build/idna-label-rules','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-label-rules.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+64],strict=True)):
            assert got==want,(label,start+offset,arguments[start+offset],got,want)
    print(f'{label}: {len(arguments)} label syntax/status comparisons PASS',flush=True)
