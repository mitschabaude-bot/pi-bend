"""Characterize nested literal pattern loading; no production compiler mutation."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--compiler',type=Path,default=ROOT/'build/bend-profiles/dns-transport-teles/bend2/main.ts')
parser.add_argument('--limit-gib',type=float,default=2)
args=parser.parse_args()
compiler=args.compiler.resolve()
prefix=ROOT/'build/compiler-nested-string-pattern'
records=[]
for suffix in ('','-shared','-equality'):
    source=ROOT/('tests/compiler-nested-string-pattern'+suffix+'.bend')
    log=Path(str(prefix)+suffix+'.log')
    stats=Path(str(prefix)+suffix+'.json')
    with log.open('w') as output:
        result=subprocess.run([sys.executable,str(ROOT/'scripts/run-rss-guarded.py'),'--limit-gib',str(args.limit_gib),'--stats',str(stats),'--',str(compiler),str(source)],cwd=ROOT,stdout=output,stderr=subprocess.STDOUT)
    text=log.read_text()
    measured=json.loads(stats.read_text())
    checked=result.returncode==0 and 'All terms check.' in text
    assert checked or measured['stopped'],text
    records.append(dict(source=str(source.relative_to(ROOT)),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),returncode=result.returncode,checked=checked,load_completed='"phase":"load-end"' in text,stats=measured,log=text))
    print(suffix or 'literal','checked' if checked else 'RSS guard stopped',measured['peak_sampled_group_rss_kib'],'KiB',flush=True)
record=dict(scope='Three intended-equivalent reduced pattern programs: inline literal/fallback, factored fallback and explicit string equality. Shared-host observations, not controlled throughput or compiler regression measurements. RSS guards sample and may overshoot; no compiler patch.',compiler=str(compiler),compiler_sha256={name:hashlib.sha256((compiler.parent/name).read_bytes()).hexdigest() for name in ('main.ts','bend.ts','comp.ts','base.bend')},harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),guard_sha256=hashlib.sha256((ROOT/'scripts/run-rss-guarded.py').read_bytes()).hexdigest(),runs=records)
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')
