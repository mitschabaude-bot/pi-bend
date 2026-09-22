"""Strict ToASCII against Unicode 17's official whole-domain conformance data."""
from itertools import product
import importlib.util
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('mapping_generator',ROOT/'scripts/generate-idna-mapping.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
for generator in ['generate-idna-mapping.py','generate-unicode-normalization.py','generate-idna-properties.py']:
    subprocess.run([sys.executable,'scripts/'+generator,'--check'],cwd=ROOT,check=True)

def unescape(value):
    if value=='""': return ''
    value=re.sub(r'\\u([0-9A-Fa-f]{4})|\\x\{([0-9A-Fa-f]+)\}',lambda m:chr(int(m[1] or m[2],16)),value)
    # Bend strings contain Unicode scalars. The corpus explicitly permits skipping
    # ill-formed inputs in such implementations; valid surrogate pairs are decoded.
    return value.encode('utf-16-le','surrogatepass').decode('utf-16-le','strict')

def statuses(value): return set(re.findall(r'[A-Z][0-9]+(?:_[0-9]+)?',value))
def codes(text): return ','.join(map(str,map(ord,text)))
corpus=[]
skipped=[]
for number,line in enumerate(data.source('IdnaTestV2.txt').splitlines(),1):
    fields=[part.strip(' \t') for part in line.split('#')[0].split(';')]
    if len(fields)<7: continue
    try: source=unescape(fields[0])
    except UnicodeError:
        skipped.append(number)
        continue
    unicode=fields[1] or fields[0]
    ascii_n=fields[3] or unicode
    status_n=fields[4] or fields[2]
    ascii_t=fields[5] or ascii_n
    status_t=fields[6] or status_n
    corpus.append((number,source,ascii_n,statuses(status_n),ascii_t,statuses(status_t)))
profiles=list(product([False,True],repeat=5))
arguments=[]
expected=[]
identifiers=[]
for hyphens,std3,joiners,bidi,dns in profiles:
    ignored=set()
    if not hyphens: ignored.update(['V2','V3'])
    if not std3: ignored.add('U1')
    if not joiners: ignored.update(['C1','C2'])
    if not bidi: ignored.update('B'+str(n) for n in range(1,7))
    if not dns: ignored.update(['A4_1','A4_2'])
    flags=';'.join(str(int(value)) for value in [hyphens,std3,joiners,bidi,dns])
    for number,source,ascii_n,status_n,ascii_t,status_t in corpus:
        for mode,result,status in [('n',ascii_n,status_n),('t',ascii_t,status_t)]:
            arguments.append(mode+';'+flags+';'+codes(source))
            expected.append('invalid' if status-ignored else '+'+codes(unescape(result)))
            identifiers.append((number,mode,flags))
assert all(len(arg)<131072 for arg in arguments), 'per-argument OS limit'

def batches():
    start=0
    while start<len(arguments):
        end=start
        size=0
        while end<len(arguments) and end-start<512 and size+len(arguments[end])+1<=262144:
            size+=len(arguments[end])+1
            end+=1
        assert end>start
        yield start,end
        start=end

print(f'{len(corpus)} scalar-input official rows, {len(skipped)} ill-formed rows inapplicable, {len(arguments)} ToASCII assertions',flush=True)
if '--prepare-only' in sys.argv: raise SystemExit(0)
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-domain.bend','build/idna-domain'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/idna-domain.bend','-o','build/idna-domain.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-domain','--threads','1']),('native 4',['build/idna-domain','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-domain.js'])]:
    for start,end in batches():
        result=subprocess.run([*command,*arguments[start:end]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:end],strict=True)):
            assert got==want,(label,identifiers[start+offset],got,want)
    print(f'{label}: {len(arguments)} official ToASCII assertions PASS',flush=True)
