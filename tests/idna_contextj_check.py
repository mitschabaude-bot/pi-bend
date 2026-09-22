"""ContextJ against independent per-joiner backward/forward rule evaluation."""
from itertools import product
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
# Joining type and canonical combining class; i/j represent ZWNJ/ZWJ.
PROPERTIES = dict(zip('abcdefghij', [('U',0),('L',0),('R',0),('D',0),('C',0),('T',230),('T',9),('U',9),('U',0),('C',0)]))

def reference(text):
    for pos, char in enumerate(text):
        if char not in 'ij':
            continue
        if pos and PROPERTIES[text[pos-1]][1] == 9:
            continue
        if char == 'j':
            return '0'
        before, after = pos-1, pos+1
        while before >= 0 and PROPERTIES[text[before]][0] == 'T':
            before -= 1
        while after < len(text) and PROPERTIES[text[after]][0] == 'T':
            after += 1
        if before < 0 or after == len(text):
            return '0'
        if PROPERTIES[text[before]][0] not in 'LD' or PROPERTIES[text[after]][0] not in 'RD':
            return '0'
    return '1'

texts = [''.join(row) for n in range(5) for row in product(PROPERTIES, repeat=n)]
rng = random.Random(5892)
texts += [''.join(rng.choice(list(PROPERTIES)) for _ in range(rng.randrange(5,128))) for _ in range(1000)]
for count in [1024,16384,65536]:
    texts += [prefix+'f'*count+suffix for prefix,suffix in
              [('bi','c'),('di','d'),('bi',''),('b','ic'),('g','j'),('g','i'),('gi',''),('bi','ji'),('a','')]]
expected = [reference(text) for text in texts]
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-contextj.bend','build/idna-contextj'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-contextj.bend','-o','build/idna-contextj.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-contextj','--threads','1']),('native 4',['build/idna-contextj','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-contextj.js'])]:
    for start in range(0,len(texts),128):
        result=subprocess.run([*command,*texts[start:start+128]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+128],strict=True)):
            assert got==want,(label,start+offset,texts[start+offset],got,want)
    print(f'{label}: {len(texts)} contextual joiner comparisons PASS',flush=True)
