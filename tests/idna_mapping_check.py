"""UTS #46 mapping against the official Unicode 17 table, over all code points."""
from bisect import bisect_right
import importlib.util
from pathlib import Path
import random
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('idna_data',ROOT/'scripts/generate-idna-mapping.py')
data=importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
subprocess.run([sys.executable,'scripts/generate-idna-mapping.py','--check'],cwd=ROOT,check=True)
raw=[]
for line in data.source('IdnaMappingTable.txt').splitlines():
    fields=[part.strip() for part in line.split('#')[0].split(';')]
    if len(fields)<2:
        continue
    limits=[int(part,16) for part in fields[0].split('..')]
    mapping=tuple(int(part,16) for part in fields[2].split()) if len(fields)>2 else ()
    raw.append((limits[0],limits[-1],fields[1],mapping))
starts=[row[0] for row in raw]

def mapped(code,transitional):
    index=bisect_right(starts,code)-1
    if index<0 or code>raw[index][1]:
        return None
    _,_,status,replacement=raw[index]
    if status=='disallowed':
        return None
    if status=='ignored':
        return ()
    # UTS #46 section 4 adds a transitional exception outside the data table.
    if code==0x1e9e and transitional:
        return (0x73,0x73)
    if status=='mapped' or status=='deviation' and transitional:
        return replacement
    assert status in ['valid','deviation']
    return (code,)

def codes(values):
    return ','.join(map(str,values))

arguments=[]
expected=[]
boundaries={0,0xD800,0xDFFF,0x10ffff,0x110000,0x110001,0xffffffff}
for first,last,_,_ in raw:
    boundaries.update(point for point in [first-1,first,last,last+1] if point>=0)
for mode in ['n','t']:
    for code in sorted(boundaries):
        value=mapped(code,mode=='t')
        arguments.append(f'p;{mode};{code}')
        expected.append('invalid;'+str(code) if value is None else '+'+codes(value))
texts=['','ẞ','ẞß.example','BÜCHER.de','faß.de','βόλος.com','\u200c\u200d','ＡＢＣ。ＣＯＭ','a\u00adb','\ufeffA','\u0000abc','a\ufffdb','\u0378','İ.K','ﬃ.test']
rng=random.Random(4617)
alphabet='abcXYZ.ßς\u200c\u200d\u00ad\u0301\ufeff\u0378\ufffdＡ。é🙂'
texts+=[''.join(rng.choice(alphabet) for _ in range(rng.randrange(40))) for _ in range(300)]
for mode in ['n','t']:
    for text in texts:
        result=[]
        for code in map(ord,text):
            value=mapped(code,mode=='t')
            if value is None:
                want='invalid;'+str(code)
                break
            result.extend(value)
        else:
            want='+'+codes(result)
        arguments.append('m;'+mode+';'+codes(map(ord,text)))
        expected.append(want)

# Official conformance examples independently fix the expected capital-sharp-S
# behavior. These inputs need no normalization beyond mapping, so their final
# Unicode/nontransitional and ASCII/transitional columns test this stage directly.
sharp_rows=[]
for line in data.source('IdnaTestV2.txt').splitlines():
    fields=[part.strip(' \t') for part in line.split('#')[0].split(';')]
    if fields[0] in ['FAẞ.de','FAẞ.DE']:
        sharp_rows.append(fields)
assert len(sharp_rows)==2
for fields in sharp_rows:
    for mode,column in [('n',1),('t',5)]:
        arguments.append('m;'+mode+';'+codes(map(ord,fields[0])))
        expected.append('+'+codes(map(ord,fields[column])))

def mix(hash_value,code):
    return ((hash_value*16777619)&0xffffffff)^code

# Check every code point, including rejected surrogate/unassigned ranges, without
# constructing invalid native Char values or sending a million CLI arguments.
for mode in ['n','t']:
    for start in range(0,0x110000,4096):
        count=min(4096,0x110000-start)
        hash_value=2166136261
        for code in range(start,start+count):
            value=mapped(code,mode=='t')
            if value is None:
                hash_value=mix(mix(hash_value,0),code)
            else:
                hash_value=mix(hash_value,1)
                for point in value:
                    hash_value=mix(hash_value,point)
                hash_value=mix(hash_value,0xffffffff)
        arguments.append(f'r;{mode};{start};{count}')
        expected.append(str(hash_value))
if '--no-build' not in sys.argv:
    subprocess.run(['sh','scripts/build-pure.sh','packages/runtime/test/idna-mapping.bend','build/idna-mapping'],cwd=ROOT,check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'),'packages/runtime/test/idna-mapping.bend','-o','build/idna-mapping.js'],cwd=ROOT,check=True)
for label,command in [('native 1',['build/idna-mapping','--threads','1']),('native 4',['build/idna-mapping','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/idna-mapping.js'])]:
    for start in range(0,len(arguments),128):
        result=subprocess.run([*command,*arguments[start:start+128]],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        for offset,(got,want) in enumerate(zip(result.stdout.splitlines(),expected[start:start+128],strict=True)):
            assert got==want,(label,start+offset,arguments[start+offset],got,want)
    print(f'{label}: {len(arguments)} mapping comparisons; all 1,114,112 code points in both modes PASS',flush=True)
