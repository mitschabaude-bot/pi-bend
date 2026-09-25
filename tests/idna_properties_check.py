"""Unicode 17 property lookup and real-text ContextJ/Bidi composition."""
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
from idna_unicode_reference import ROOT, data, boundaries, properties, context

arguments=[]
expected=[]
for code in sorted(boundaries):
    arguments.append(f'p;{code}')
    expected.append(';'.join(map(str,properties(code))) if code<=0x10ffff else 'none')
for start in range(0,0x110000,4096):
    count=min(4096,0x110000-start)
    value=2166136261
    for code in range(start,start+count):
        for part in properties(code): value=((value*16777619)&0xffffffff)^part
    arguments.append(f'r;{start};{count}')
    expected.append(str(value))
examples=['example','123','é','אב','اب','نامه\u200cای','क्\u200dष','क्\u200cष','a\u200db','a\u200cb','\u0301a','क्\u0301\u200dष','ب\u200cب','ب\u064e\u200c\u064eب','ب\u200c','ب\u200c\u200cب','אב1','אב١','אב1١']
# Node comparison is a separate pending compatibility review: its current
# implementation does not enforce all ContextJ conditions (see parity record).
texts=['',*examples,'ب\u200c\u200dب','ب-\u200cب','क्\u200da\u200cb','क्\u200dאב']
rng=random.Random(1705892)
alphabet='abcאבاب١1\u200c\u200d\u0301\u094d\u064e\u202e\u2066🙂'
texts+=[''.join(rng.choice(alphabet) for _ in range(rng.randrange(80))) for _ in range(1000)]
for text in texts:
    arguments.append('s;'+','.join(map(str,map(ord,text))))
    expected.append(context(text))
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/idna-properties.bend','build/idna-properties'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-properties.bend','-o','build/idna-properties.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-properties','--threads','1']),('native 4',['build/idna-properties','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-properties.js'])]:
    for start in range(0,len(arguments),128):
        result=subprocess.run([*command,*arguments[start:start+128]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+128],strict=True)):
            assert got==want,(label,start+offset,arguments[start+offset],got,want)
    print(f'{label}: {len(arguments)} property/context comparisons PASS',flush=True)
