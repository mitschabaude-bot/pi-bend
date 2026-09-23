"""Unicode17 lowercase: pinned rules, test-only ECMAScript oracle, all scalar mappings."""
import argparse, importlib.util, itertools, json, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('case_data',ROOT/'scripts/generate-case-map.py')
gen=importlib.util.module_from_spec(spec);spec.loader.exec_module(gen)
p=argparse.ArgumentParser(description=__doc__);p.add_argument('backends',nargs='*',default=['bun','native-1','native-4']);a=p.parse_args()
mapping,props=gen.data()
def reference(text):
    cps=list(map(ord,text));out=[]
    for index,cp in enumerate(cps):
        if cp==0x3a3:
            before=index-1;after=index+1
            while before>=0 and props[cps[before]]&2:before-=1
            while after<len(cps) and props[cps[after]]&2:after+=1
            final=before>=0 and props[cps[before]]&1 and not(after<len(cps) and props[cps[after]]&1)
            out.append(0x3c2 if final else 0x3c3)
        else:out.extend(mapping.get(cp,[cp]))
    return ''.join(map(chr,out))
def digest(cps):
    value=2166136261
    for cp in cps:value=((value*16777619)&0xffffffff)^cp
    return str(value)
domain=digest(out for cp in range(0x110000) if not 0xd800<=cp<0xe000 for out in mapping.get(cp,[cp]))
# Every explicitly mapped scalar is compared exactly, including identity entries.
cases=[''.join(map(chr,[cp])) for cp in mapping]
units=['A','a','Σ','ς','İ','ß','\u0301',"'",'\u0345','\u200d','\u00ad',' ','1','😀','\u2160']
cases += [''.join(parts) for parts in itertools.product(units,repeat=3) if 'Σ' in parts]
cases += ['ΟΣ','ΟΣΑ','Σ','ΣΣ','AΣ\u0301','AΣ\u0301B','Iİıi','ǅẞKﬃ','AΣ\u0345','A\u0345Σ']
expected=list(map(reference,cases))
# Host runs only as a test oracle. Node reports its ICU/Unicode versions below.
versions=subprocess.check_output(['node','-p','JSON.stringify({icu:process.versions.icu,unicode:process.versions.unicode})'],text=True).strip()
for first in range(0,len(cases),64):
    oracle=json.loads(subprocess.check_output(['node','-e','console.log(JSON.stringify(JSON.parse(process.argv[1]).map(s=>s.toLowerCase())))',json.dumps(cases[first:first+64])],text=True))
    assert oracle==expected[first:first+64],('host Unicode version mismatch or mapping disagreement',versions,first)
long=['AΣ'+'\u0301'*100000,'AΣ'+'\u0301'*100000+'A',('Σ\u0301')*50000,'İ'*50000]
# Avoid a quadratic test oracle on repeated context; these expectations follow
# directly from Final_Sigma and the unconditional expansion.
long_results=['aς'+'\u0301'*100000,'aσ'+'\u0301'*100000+'a',('σ\u0301')*49999+'ς\u0301',('i\u0307')*50000]
long_expected=[str(len(s))+':'+digest(map(ord,s)) for s in long_results]
for backend in a.backends:
    cmd=['bun','build/case-map.js'] if backend=='bun' else ['build/case-map','--threads',backend[-1]]
    for first in range(0,len(cases),64):
        actual=[json.loads(line) for line in subprocess.check_output(cmd+[json.dumps(cases[first:first+64])],cwd=ROOT,text=True,timeout=30).splitlines()]
        assert actual==expected[first:first+64],(backend,first,actual,expected[first:first+64])
    start=time.monotonic()
    actual=subprocess.check_output(cmd+['domain'],cwd=ROOT,text=True,timeout=90).strip()
    assert actual==domain,(backend,actual,domain)
    result=subprocess.run(cmd+['long'],cwd=ROOT,capture_output=True,text=True,timeout=60)
    assert result.returncode==0 and not result.stderr,(backend,result.stderr)
    assert result.stdout.splitlines()==long_expected,(backend,result.stdout,long_expected)
    print(f'{backend}: {len(cases)} exact mappings/context cases, full scalar-domain digest, four long cases pass ({time.monotonic()-start:.3f}s); oracle {versions}',flush=True)
