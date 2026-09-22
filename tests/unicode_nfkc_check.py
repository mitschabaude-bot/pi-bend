"""Unicode17 NFKC conformance: all five source columns must normalize to c4."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('unicode_data',ROOT/'scripts/generate-unicode-normalization.py')
data=importlib.util.module_from_spec(spec);spec.loader.exec_module(data)
cases={():()}
for row in data.source('NormalizationTest.txt').splitlines():
    row=row.split('#')[0].strip()
    if not row or row.startswith('@'):continue
    cols=[tuple(int(v,16) for v in col.split()) for col in row.split(';')[:5]]
    for col in cols:
        assert col not in cases or cases[col]==cols[3]
        cases[col]=cols[3]
items=list(cases.items())
binary=os.environ.get('EDIT_DIFF_BINARY','build/edit-diff')
commands=[] if '--native-only' in sys.argv else [('Bun',['bun','build/edit-diff.js'])]
if '--bun-only' not in sys.argv:
    commands += [('native1',[binary,'--threads','1']),('native4',[binary,'--threads','4'])]
for name,command in commands:
    for start in range(0,len(items),128):
        batch=items[start:start+128]
        args=['n|'+','.join(map(str,points)) for points,_ in batch]
        expected=[','.join(map(str,points)) for _,points in batch]
        p=subprocess.run(command+args,cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert p.returncode==0 and not p.stderr,(name,start,p.stderr[:1000])
        actual=p.stdout.splitlines()
        assert len(actual)==len(expected),(name,start,len(actual),len(expected))
        for i,(got,want) in enumerate(zip(actual,expected)):
            assert got==want,(name,start+i,batch[i],got,want)
    print(f'{name}: {len(items)} Unicode17 NFKC conformance comparisons PASS',flush=True)
