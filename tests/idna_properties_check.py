"""Unicode 17 property lookup and real-text ContextJ/Bidi composition."""
from bisect import bisect_right
import importlib.util
from pathlib import Path
import random
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('property_generator',ROOT/'scripts/generate-idna-properties.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
subprocess.run([sys.executable,'scripts/generate-idna-properties.py','--check'],cwd=ROOT,check=True)
# Independent interval lookup: explicit assignments first, then the last matching
# default. The generator instead expands defaults/overrides and coalesces tuples.
boundaries={0,0x10ffff,0x110000,0xffffffff}
def intervals(name):
    explicit,defaults=[],[]
    for line in data.source(name).splitlines():
        target=defaults if '@missing:' in line else explicit
        line=line.split('@missing:')[1] if '@missing:' in line else line.split('#')[0]
        if not line.strip():
            continue
        limits,value=[part.strip() for part in line.split(';')]
        ends=[int(part,16) for part in limits.split('..')]
        first,last=ends[0],ends[-1]
        target.append((first,last,data.ALIASES.get(value,value)))
        boundaries.update(point for point in [first-1,first,last,last+1] if point>=0)
    explicit.sort()
    return explicit,[row[0] for row in explicit],defaults
bidi=intervals('DerivedBidiClass.txt')
joining=intervals('DerivedJoiningType.txt')
def lookup(table,code):
    rows,starts,defaults=table
    index=bisect_right(starts,code)-1
    if index>=0 and code<=rows[index][1]:
        return rows[index][2]
    for first,last,value in reversed(defaults):
        if first<=code<=last:
            return value
    raise AssertionError(code)

# UnicodeData's First/Last ranges have no marks or nonzero combining classes.
# Assert that fact rather than silently dropping such values if data changes.
marks=set()
ccc={}
for line in (ROOT/'build/unicode-17/UnicodeData.txt').read_text().splitlines():
    fields=line.split(';')
    code=int(fields[0],16)
    if fields[1].endswith((', First>',', Last>')):
        assert not fields[2].startswith('M') and fields[3]=='0'
    if fields[2].startswith('M'):
        marks.add(code)
    if int(fields[3]):
        ccc[code]=int(fields[3])
    boundaries.update(point for point in [code-1,code,code+1] if point>=0)

def properties(code):
    return data.BIDI.index(lookup(bidi,code)), 'ULRDCT'.index(lookup(joining,code)), ccc.get(code,0), int(code in marks)

def context(text):
    codes=list(map(ord,text))
    classes=[lookup(bidi,code) for code in codes]
    present=set(classes)
    rtl=bool(present & {'R','AL','AN'})
    ending=[value for value in classes if value!='NSM']
    valid=False
    if classes and classes[0] in {'R','AL'}:
        valid=(present <= {'R','AL','AN','EN','ES','CS','ET','ON','BN','NSM'} and ending[-1] in {'R','AL','EN','AN'} and not {'EN','AN'}<=present)
    elif classes and classes[0]=='L':
        valid=(present <= {'L','EN','ES','CS','ET','ON','BN','NSM'} and ending[-1] in {'L','EN'})
    joiners=True
    for pos,code in enumerate(codes):
        if code not in [0x200c,0x200d] or pos and ccc.get(codes[pos-1],0)==9:
            continue
        if code==0x200d:
            joiners=False
            break
        left,right=pos-1,pos+1
        while left>=0 and lookup(joining,codes[left])=='T': left-=1
        while right<len(codes) and lookup(joining,codes[right])=='T': right+=1
        if left<0 or right==len(codes) or lookup(joining,codes[left]) not in {'L','D'} or lookup(joining,codes[right]) not in {'R','D'}:
            joiners=False
            break
    return ''.join(str(int(value)) for value in [bool(codes and codes[0] in marks),rtl,valid,joiners])

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
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-properties.bend','build/idna-properties'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/idna-properties.bend','-o','build/idna-properties.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-properties','--threads','1']),('native 4',['build/idna-properties','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-properties.js'])]:
    for start in range(0,len(arguments),128):
        result=subprocess.run([*command,*arguments[start:start+128]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+128],strict=True)):
            assert got==want,(label,start+offset,arguments[start+offset],got,want)
    print(f'{label}: {len(arguments)} property/context comparisons PASS',flush=True)
