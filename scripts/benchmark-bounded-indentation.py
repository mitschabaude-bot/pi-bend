"""Compare minimal indentation bounding with the otherwise identical compiler.

Usage: python3 scripts/benchmark-bounded-indentation.py CANDIDATE_BEND2 OUTPUT_JSON [min|slice]
Measures fresh-process load/check/C emission. Does not measure program runtime.
"""
import hashlib
import itertools
import json
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
baseline=Path.home()/'.bend/current/bend2'
candidate=Path(sys.argv[1]).resolve()
destination=Path(sys.argv[2])
bun=Path.home()/'.bun/bin/bun'
old='fl.seg.lines.push("  ".repeat(fl.tab) + line);'
new='fl.seg.lines.push("  ".repeat(Math.min(fl.tab, 16)) + line);'
strategy=sys.argv[3] if len(sys.argv)>3 else 'min'
assert strategy in ['min','slice']
original=(baseline/'comp.ts').read_text()
assert original.count(old)==1
expected=original.replace(old,new) if strategy=='min' else original.replace('function file_push(fl: File, line: string): void {', 'const FILE_INDENT = "  ".repeat(16);\n\nfunction file_push(fl: File, line: string): void {').replace(old,'fl.seg.lines.push(FILE_INDENT.slice(0, fl.tab * 2) + line);')
assert (candidate/'comp.ts').read_text()==expected
for path in baseline.rglob('*'):
    if path.is_file() and path.relative_to(baseline).as_posix()!='comp.ts':
        assert path.read_bytes()==(candidate/path.relative_to(baseline)).read_bytes(),path

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def compare(before,after):
    normalized=hashlib.sha256();changed=0
    with before.open('rb') as a,after.open('rb') as b:
        for index,(left,right) in enumerate(itertools.zip_longest(a,b),1):
            assert left is not None and right is not None,(before,index,'line count')
            left_text=left.lstrip(b' ');right_text=right.lstrip(b' ')
            assert left_text==right_text,(before,index,'non-indentation changed')
            if left!=right:
                assert len(left)-len(left_text)>32 and len(right)-len(right_text)==32,(before,index,'unexpected indentation')
                changed+=1
            normalized.update(left_text)
    return dict(normalized_sha256=normalized.hexdigest(),changed_lines=changed)

folder=ROOT/('build/indent-benchmark-'+strategy)
folder.mkdir(exist_ok=True)
result={'scope':__doc__,'strategy':strategy,'shared_host':True,'kernel':platform.release(),'bun':subprocess.check_output([str(bun),'--version'],text=True).strip(),
        'compiler_sha256':{'baseline':digest(baseline/'comp.ts'),'candidate':digest(candidate/'comp.ts')},
        'method':'Fresh Bun process; two warmups then 20 alternating-order rounds for ordinary fixtures; one warmup then five rounds for the large reproducer. Individual GNU time peak RSS and CPU usage. Compare output after every pair; only leading indentation beyond 32 spaces may change. No runtime-throughput claim.',
        'fixtures':{}}
for source,rounds,warmups in [('tests/typed-do-shadow.bend',20,2),('packages/runtime/test/utf8-runner.bend',20,2),('tests/compiler-long-string-patterns.bend',5,1)]:
    name=Path(source).stem
    artifact=folder/name
    artifact.mkdir(exist_ok=True)
    samples={'baseline':[],'candidate':[]}
    for round_index in range(-warmups,rounds):
        order=['candidate','baseline'] if round_index%2 else ['baseline','candidate']
        for variant in order:
            compiler=baseline if variant=='baseline' else candidate
            output=artifact/(variant+'.c');usage=artifact/'usage.txt'
            started=time.perf_counter()
            run=subprocess.run(['/usr/bin/time','-f','%U %S %M','-o',str(usage),str(bun),str(compiler/'main.ts'),source,'-o',str(output)],cwd=ROOT,capture_output=True,text=True,timeout=120)
            assert run.returncode==0,(variant,source,run.stdout,run.stderr)
            elapsed=time.perf_counter()-started
            user,system,rss=usage.read_text().split()
            if round_index>=0:samples[variant].append(dict(wall_seconds=elapsed,cpu_user_seconds=float(user),cpu_system_seconds=float(system),peak_rss_kib=int(rss)))
        comparison=compare(artifact/'baseline.c',artifact/'candidate.c')
    medians={variant:{key:statistics.median(row[key] for row in rows) for key in ['wall_seconds','cpu_user_seconds','cpu_system_seconds','peak_rss_kib']} for variant,rows in samples.items()}
    result['fixtures'][source]=dict(source_sha256=digest(ROOT/source),samples=samples,medians=medians,
        candidate_over_baseline={key:medians['candidate'][key]/medians['baseline'][key] for key in ['wall_seconds','peak_rss_kib']},
        generated_c={variant:dict(bytes=(artifact/(variant+'.c')).stat().st_size,sha256=digest(artifact/(variant+'.c'))) for variant in samples},comparison=comparison)
    rng=random.Random(16)
    ratios=[b['wall_seconds']/a['wall_seconds'] for a,b in zip(samples['baseline'],samples['candidate'])]
    estimates=sorted(statistics.median(rng.choices(ratios,k=len(ratios))) for _ in range(10000))
    result['fixtures'][source]['paired_wall_ratio_bootstrap']={
        'method':'Median of per-round candidate/baseline wall ratios; 10000 paired bootstrap resamples, random seed 16. Shared-host exploratory uncertainty estimate, not proof of performance equivalence.',
        'median':statistics.median(ratios),'percentile_95_interval':[estimates[249],estimates[9749]]}
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(result,indent=2)+'\n')
    print(source,json.dumps(result['fixtures'][source]['candidate_over_baseline']),flush=True)
