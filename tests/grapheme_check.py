"""Unicode17 conformance, actual Intl.Segmenter comparison, and long native runs."""
import importlib.util
import json
import random
import subprocess
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('grapheme_data',ROOT/'scripts/generate-grapheme.py');data=importlib.util.module_from_spec(spec);spec.loader.exec_module(data)

cases=[];expected=[]
for line in data.source('auxiliary/GraphemeBreakTest.txt').splitlines():
    body=line.split('#')[0].strip()
    if not body:continue
    clusters=[];part=''
    for item in body.split():
        if item=='÷':
            if part:clusters.append(part);part=''
        elif item!='×':part+=chr(int(item,16))
    assert not part
    cases.append(''.join(clusters));expected.append(clusters)
conformance=len(cases)
cases+=['','a','\r\n','👩\u200d👩\u200d👧\u200d👦','क्\u200dक','🇦🇧🇨🇩🇪','a\u0301','\u0600\r\n']
expected+=[[],['a'],['\r\n'],['👩\u200d👩\u200d👧\u200d👦'],['क्\u200dक'],['🇦🇧','🇨🇩','🇪'],['a\u0301'],['\u0600','\r\n']]
values=data.properties();rng=random.Random(170029)
# Property-run starts/ends exercise actual generated decisions as well as rules.
points={0,0x10ffff}
for cp in range(1,len(values)):
    if values[cp]!=values[cp-1]:points.update([cp-1,cp])
points=sorted(cp for cp in points if not 0xd800<=cp<=0xdfff)
random_cases=[]
for _ in range(1500):
    random_cases.append(''.join(chr(rng.choice(points)) for _ in range(rng.randrange(1,30))))
for _ in range(1500):
    random_cases.append(''.join(rng.choice(['a','\u0301','\u200d','👩','🇦','🇧','क','्','\u093c','\u0600','\r','\n','ᄀ','ᅡ','ᆨ']) for _ in range(rng.randrange(1,40))))
reference=json.loads(subprocess.check_output(['node','tests/grapheme_reference.mjs'],input=json.dumps(cases+random_cases),text=True,cwd=ROOT))
assert reference[:len(expected)]==expected,'Node17 disagrees with Unicode17 official corpus or explicit cases'
cases+=random_cases;expected=reference
long_texts=['a'+'\u0301'*100000,'👩'+'\u0301\u200d👩'*20000,'🇦'*50000,'क'+'्क'*30000,'a'*100000]
long_counts=[1,1,25000,1,100000]
def summary(text,count):
    value=2166136261
    for char in text:value=((value*16777619)&0xffffffff)^ord(char)
    return f'{count}:{len(text)}:{value}'
long_expected=[summary(text,count) for text,count in zip(long_texts,long_counts) for _ in range(2)]
for name,command in [('bun',['bun','build/grapheme.js']),('native1',['build/grapheme','--threads','1']),('native4',['build/grapheme','--threads','4'])]:
    begin=time.monotonic()
    for first in range(0,len(cases),64):
        raw=subprocess.check_output(command+[json.dumps(cases[first:first+64])],text=True,cwd=ROOT,timeout=30)
        actual=[json.loads(line) for line in raw.split('\n') if line]
        wanted=[[clusters,clusters] for clusters in expected[first:first+64]]
        assert actual==wanted,(name,first,actual,wanted)
    elapsed=time.monotonic()-begin
    begin=time.monotonic();result=subprocess.run(command+['long'],text=True,capture_output=True,cwd=ROOT,timeout=60)
    assert result.returncode==0,(name,result.stderr)
    assert result.stdout.splitlines()==long_expected,(name,result.stdout,long_expected)
    print(name,conformance,'official cases +',len(cases)-conformance,'explicit/Intl comparisons; next and segments; long scans',round(time.monotonic()-begin,3),'s; corpus',round(elapsed,3),'s',flush=True)
