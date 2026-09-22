"""Exhaustive Unicode simple-fold cycles, literal equality and class membership."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import runpy
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
generator = runpy.run_path(str(ROOT / 'scripts/generate-case-fold.py'))
mapping = generator['mappings']()
uppercase = generator['uppercase']()
groups = defaultdict(set)
for source, target in mapping.items():
    groups[target].update([source, target])
classes = {code: group for group in groups.values() for code in group}
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/case-fold')
p.add_argument('--reference',type=Path,help='unpacked pinned ignore@7.0.8 package')
a = p.parse_args()

# Explicit ranges exercise matching original endpoints against the complete
# equivalence class, including punctuation and singleton non-ASCII ranges.
ranges = [(ord(c), first, last) for c in 'aAzZéÉσςΣµΜμkKKsSſßẞǄǅǆİı😀𐐀𐐨'
          for first, last in [(65,90),(97,122),(91,96),(0x3a3,0x3a3),(0xdf,0xdf),(0x212a,0x212a),(0x10400,0x10427)]]
pairs = [(ord(a),ord(b)) for a,b in [('é','É'),('σ','ς'),('ς','Σ'),('µ','Μ'),('K','K'),('ſ','s'),('ß','ẞ'),('Ǆ','ǆ'),('𐐀','𐐨'),('İ','i'),('ı','I'),('ß','s'),('é','e'),('😀','😁'),('[','{')]]

for backend in a.backends:
    prefix = ['bun',str(a.prefix)+'.js'] if backend == 'bun' else [str(a.prefix),'--threads',backend[-1]]
    def run(*args):
        completed = subprocess.run(prefix + list(map(str,args)),capture_output=True,text=True,timeout=30)
        assert completed.returncode == 0 and not completed.stderr, (backend,args,completed.stdout[-1000:],completed.stderr)
        return completed.stdout.splitlines()
    started = time.monotonic()
    observed = {}
    for line in run('scan',0,0xd800) + run('scan',0xe000,0x110000-0xe000):
        code,*values = map(int,line.split(','))
        assert code not in observed and values[0] == code and len(values) == len(set(values)), (code,values)
        observed[code] = set(values)
    assert observed == classes, backend
    observed_uppercase = {int(code) for code in run("uppercase",0,0xd800)+run("uppercase",0xe000,0x110000-0xe000)}
    assert observed_uppercase == uppercase, (backend,observed_uppercase ^ uppercase)
    elapsed = time.monotonic()-started
    for left,right in pairs:
        expected = mapping.get(left,left) == mapping.get(right,right)
        assert run('equal',left,right) == [str(expected).lower()], (backend,left,right)
    for code,first,last in ranges:
        expected = any(first <= value <= last for value in classes.get(code,{code}))
        assert run('range',code,first,last) == [str(expected).lower()], (backend,code,first,last)
    print(f'{backend}: all 1,112,064 Unicode scalars checked ({elapsed:.3f}s), 2,994 class members, symmetric equality, {len(uppercase)} Uppercase scalars, {len(pairs)} literal / {len(ranges)} range cases PASS',flush=True)

if a.reference:
    source_pairs = list(mapping.items())
    cases = [[chr(left),chr(right)] for left,right in source_pairs]
    result = subprocess.run(['bun',str(ROOT/'tests/case_fold_reference.mjs'),str(a.reference.resolve())],
                            input=json.dumps(cases),capture_output=True,text=True,check=True)
    reference = json.loads(result.stdout)
    legacy = reference['legacy']
    assert reference['unicode'] == [True] * len(cases), 'Unicode-mode reference disagrees'
    assert len(legacy) == len(cases)
    different = [pair for pair,matched in zip(source_pairs,legacy) if not matched]
    bmp = [(left,right) for left,right in different if left <= 0xffff and right <= 0xffff]
    print(f'ignore@7.0.8: {len(cases)-len(different)} of {len(cases)} official mapping pairs agree; '
          f'{len(bmp)} BMP and {len(different)-len(bmp)} supplementary intentional legacy /i differences',flush=True)
    # Representative semantic changes stay explicit; never weaken Unicode's oracle.
    for pair in [(0x17f,0x73),(0x212a,0x6b),(0x1e9e,0xdf),(0x10400,0x10428)]:
        assert pair in different,pair
