"""Compare weak telescope caching with an otherwise identical compiler.

Fresh-process time and individual peak RSS; exact output required after every
pair. Shared-host observations do not prove universal performance neutrality.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('candidate',ROOT/'scripts/prepare-weak-teles-candidate.py')
prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)
candidate=Path(sys.argv[1]).resolve();destination=Path(sys.argv[2])
prepare.verify(candidate)
baseline=prepare.BASELINE;bun=Path.home()/'.bun/bin/bun'
folder=ROOT/'build/weak-teles-benchmark';folder.mkdir(exist_ok=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
result={'scope':__doc__,'shared_host':True,'kernel':platform.release(),'bun':subprocess.check_output([str(bun),'--version'],text=True).strip(),
        'compiler_sha256':{'baseline':digest(baseline/'comp.ts'),'candidate':digest(candidate/'comp.ts')},
        'method':'Two warmups followed by 20 alternating-order pairs. Fresh Bun without --smol or forced GC. GNU time individual child peak RSS and CPU. Require byte-identical generated C after every pair. No runtime-throughput claim.', 'fixtures':{}}
for source in ['tests/typed-do-shadow.bend','packages/runtime/test/utf8-runner.bend','tests/compiler-string-match.bend','packages/runtime/test/url-authority.bend']:
    out=folder/Path(source).stem;out.mkdir(exist_ok=True)
    samples={'baseline':[],'candidate':[]}
    for round_index in range(-2,20):
        order=['candidate','baseline'] if round_index%2 else ['baseline','candidate']
        for variant in order:
            compiler=baseline if variant=='baseline' else candidate
            output=out/(variant+'.c');usage=out/'usage.txt'
            started=time.perf_counter()
            run=subprocess.run(['/usr/bin/time','-f','%U %S %M','-o',str(usage),str(bun),str(compiler/'main.ts'),source,'-o',str(output)],cwd=ROOT,capture_output=True,text=True,timeout=120)
            assert run.returncode==0,(variant,source,run.stdout,run.stderr)
            elapsed=time.perf_counter()-started
            user,system,rss=usage.read_text().split()
            if round_index>=0:samples[variant].append(dict(wall_seconds=elapsed,cpu_user_seconds=float(user),cpu_system_seconds=float(system),peak_rss_kib=int(rss)))
        assert (out/'baseline.c').read_bytes()==(out/'candidate.c').read_bytes(),(source,round_index,'generated C differs')
    medians={variant:{key:statistics.median(row[key] for row in rows) for key in ['wall_seconds','cpu_user_seconds','cpu_system_seconds','peak_rss_kib']} for variant,rows in samples.items()}
    ratios=[b['wall_seconds']/a['wall_seconds'] for a,b in zip(samples['baseline'],samples['candidate'],strict=True)]
    rng=random.Random(20260929)
    estimates=sorted(statistics.median(rng.choices(ratios,k=len(ratios))) for _ in range(10000))
    summary={'source_sha256':digest(ROOT/source),'samples':samples,'medians':medians,
             'candidate_over_baseline':{key:medians['candidate'][key]/medians['baseline'][key] for key in ['wall_seconds','peak_rss_kib']},
             'paired_wall_ratio_bootstrap':{'median':statistics.median(ratios),'percentile_95_interval':[estimates[249],estimates[9749]],'resamples':10000,'seed':20260929},
             'generated_c_bytes':(out/'baseline.c').stat().st_size,'generated_c_sha256':digest(out/'baseline.c'),'exact_C_identical_every_pair':True}
    result['fixtures'][source]=summary
    destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(json.dumps(result,indent=2)+'\n')
    print(source,json.dumps(summary['candidate_over_baseline']),json.dumps(summary['paired_wall_ratio_bootstrap']),flush=True)
