"""Paired loopback performance of UDP effects before and after cancellation refactoring.

No adoption decision is automatic. Whole-process time/RSS include startup and
payload verification. This does not benchmark cancellation or real backpressure.
"""
import argparse,hashlib,json,os,random,shutil,statistics,subprocess,time
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--iterations',type=int,default=30000)
parser.add_argument('--trials',type=int,default=7)
parser.add_argument('--backend',choices=['native 1','native 4','Bun'],action='append')
args=parser.parse_args();assert args.iterations>0 and args.trials>=3
bun=Path.home()/'.bun/bin/bun'
current=TOOLCHAIN
baseline=TOOLCHAIN
revision='8cc63fc'
effects=['udp_recv_bytes.c','udp_recv_bytes.js','udp_send_bytes.c','udp_send_bytes.js']
if not baseline.exists():shutil.copytree(current,baseline)
for name in effects:
    old=subprocess.check_output(['git','show',f'{revision}:patches/experimental/udp-bytes/{name}'],cwd=ROOT)
    (baseline/'effs'/name).write_bytes(old)
for path in current.rglob('*'):
    relative=path.relative_to(current)
    if path.is_file() and relative.as_posix() not in ['effs/'+n for n in effects]:
        assert path.read_bytes()==(baseline/relative).read_bytes(),relative
builds={};hashes={}
for name,candidate in [('baseline',baseline),('candidate',current)]:
    for suffix in ['c','js']:
        stats=f'build/udp-throughput-{name}-{suffix}-build.json'
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',stats,'--',str(bun),str(candidate/'main.ts'),'tests/udp-throughput.bend','-o',f'build/udp-throughput-{name}.{suffix}'],cwd=ROOT,check=True)
        builds[name+'-'+suffix]=json.loads((ROOT/stats).read_text())
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O2',f'build/udp-throughput-{name}.c','-lpthread','-lm','-o',f'build/udp-throughput-{name}'],cwd=ROOT,check=True)
    hashes[name]={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']+['effs/'+n for n in effects]}
rows=[];summaries=[]
for backend in args.backend or ['native 1','native 4','Bun']:
    for family in [4,6]:
        for size in [0,256]:
            samples={name:[] for name in ['baseline','candidate']}
            for trial in range(-1,args.trials):
                for name in (['baseline','candidate'] if trial%2 else ['candidate','baseline']):
                    command=[str(bun),f'build/udp-throughput-{name}.js'] if backend=='Bun' else [f'build/udp-throughput-{name}','--threads',backend[-1]]
                    stats=ROOT/'build/udp-throughput-process.txt'
                    start=time.perf_counter()
                    run=subprocess.run(['/usr/bin/time','-f','%e %U %S %M','-o',str(stats),*command,str(family),str(args.iterations),str(size)],cwd=ROOT,capture_output=True,text=True,timeout=60)
                    wall=time.perf_counter()-start
                    assert run.returncode==0 and run.stdout=='ok\n' and not run.stderr,(backend,family,size,name,run)
                    elapsed,user,system,rss=map(float,stats.read_text().split())
                    if trial<0:continue
                    sample=dict(backend=backend,family=family,size=size,trial=trial,version=name,wall_seconds=wall,user_seconds=user,system_seconds=system,peak_rss_kib=rss)
                    rows.append(sample);samples[name].append(sample)
            ratios=[c['wall_seconds']/b['wall_seconds'] for b,c in zip(samples['baseline'],samples['candidate'])]
            rng=random.Random(0)
            medians=sorted(statistics.median(rng.choices(ratios,k=len(ratios))) for _ in range(2000))
            summary=dict(backend=backend,family=family,size=size,median_paired_time_ratio=statistics.median(ratios),paired_ratio_range=[min(ratios),max(ratios)],bootstrap_median_ratio_interval_95=[medians[49],medians[1949]],median_seconds={k:statistics.median(r['wall_seconds'] for r in v) for k,v in samples.items()},median_peak_rss_kib={k:statistics.median(r['peak_rss_kib'] for r in v) for k,v in samples.items()})
            summaries.append(summary)
            print(json.dumps(summary),flush=True)
result=dict(scope=__doc__,baseline_revision=revision,iterations=args.iterations,trials=args.trials,environment=dict(uname=list(os.uname()),bun=subprocess.check_output([str(bun),'--version'],text=True).strip(),clang=subprocess.check_output(['clang','--version'],text=True).splitlines()[0]),sources={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ['tests/udp-throughput.bend','tests/udp_performance_check.py']},compiler_and_effect_hashes=hashes,builds=builds,summaries=summaries,runs=rows)
(ROOT/'build/udp-performance-result.json').write_text(json.dumps(result,indent=2)+'\n')
