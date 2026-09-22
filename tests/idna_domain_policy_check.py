"""Whole-domain Bidi aggregation and strict UTS #46 ASCII DNS lengths."""
from itertools import product
import importlib.util
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
arguments=[]
expected=[]
for n in range(6):
    for parts in product('abcde',repeat=n):
        value=''.join(parts)
        # c/d have RTL; b/d violate the label rule. e is an empty label.
        valid=not any(c in value for c in 'cd') or not any(c in value for c in 'bd')
        arguments.append('b;'+value)
        expected.append(str(int(valid)))
for value in ['b'+'a'*8192+'c','c'+'a'*8192+'b','b'+'a'*8192,'e'*8192+'c']:
    arguments.append('b;'+value)
    expected.append(str(int(not any(c in value for c in 'cd') or not any(c in value for c in 'bd'))))

def dns(value):
    labels=value.split('.')
    # DNS wire representation includes one length octet per label and a final
    # root octet. Strict UTS #46 additionally requires every input label nonempty.
    return all(value.isascii() and 1<=len(value)<=63 for value in labels) and sum(len(value)+1 for value in labels)+1<=255

def add(value,want=None):
    if want is None: want=dns(value)
    arguments.append('d;'+','.join(map(str,map(ord,value))))
    expected.append(str(int(want)))

values=['','.','..','a.','.a','a..b','a.b','é','xn--bcher-kva','\x00','\x7f','\x80']
values += ['a'*length for length in [1,62,63,64,252,253,254,255,256,8192]]
for lengths in product([0,1,62,63,64],repeat=3):
    value='.'.join('a'*length for length in lengths)
    values.extend([value,value+'.'])
for last in range(56,65):
    values.extend(['.'.join(['a'*63]*3+['b'*last]),'.'.join(['a'*63]*3+['b'*last])+'.'])
values += ['.'.join(['a']*count) for count in [126,127,128,129,8192]]
rng=random.Random(1035)
values += ['.'.join('a'*rng.randrange(70) for _ in range(rng.randrange(8))) for _ in range(500)]
for value in values: add(value)

spec=importlib.util.spec_from_file_location('mapping_generator',ROOT/'scripts/generate-idna-mapping.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
def unescape(value):
    if value=='""': return ''
    return re.sub(r'\\u([0-9A-Fa-f]{4})|\\x\{([0-9A-Fa-f]+)\}',lambda m:chr(int(m[1] or m[2],16)),value)
official=0
for line in data.source('IdnaTestV2.txt').splitlines():
    fields=[part.strip(' \t') for part in line.split('#')[0].split(';')]
    if len(fields)<7: continue
    unicode=fields[1] or fields[0]
    ascii_n=fields[3] or unicode
    status_n=fields[4] or fields[2]
    ascii_t=fields[5] or ascii_n
    status_t=fields[6] or status_n
    for encoded,status in [(ascii_n,status_n),(ascii_t,status_t)]:
        value=unescape(encoded)
        if not value.isascii(): continue
        valid=not any(code in status for code in ['A4_1','A4_2'])
        assert dns(value)==valid,(value,status)
        add(value,valid)
        official+=1
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-domain-policy.bend','build/idna-domain-policy'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-domain-policy.bend','-o','build/idna-domain-policy.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-domain-policy','--threads','1']),('native 4',['build/idna-domain-policy','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-domain-policy.js'])]:
    for start in range(0,len(arguments),64):
        result=subprocess.run([*command,*arguments[start:start+64]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+64],strict=True)):
            assert got==want,(label,start+offset,arguments[start+offset],got,want)
    print(f'{label}: {len(arguments)} domain policy comparisons PASS ({official} official ASCII length assertions)',flush=True)
