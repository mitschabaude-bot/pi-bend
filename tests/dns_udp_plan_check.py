"""Compiled composition of position assignment, timeout budgets, rotation and retry order."""
import hashlib,itertools,json,re,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-udp-plan-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/dns-udp-plan.bend','-o',f'build/dns-udp-plan.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-udp-plan.c','-lpthread','-lm','-o','build/dns-udp-plan'],cwd=ROOT,check=True)
cases=[]
for timeout,count,offset,attempts in itertools.product([0,5,30,31],range(5),[0,1,2,5],[0,1,3]):
    if count==0:expected='no-servers'
    elif count>3:expected='too-many'
    elif timeout>30:expected=f'invalid:{timeout}'
    else:
        entries=[]
        for index in range(count):
            role='first' if index==0 else 'second2' if count==2 else 'second3' if index==1 else 'third3'
            seconds=max(1,timeout if index==0 else (timeout<<index)//count)
            entries.append(f'{index%2}@{role}={seconds};')
        shift=offset%count
        expected=''.join(entries[shift:]+entries[:shift])*attempts
    cases.append(dict(timeout=timeout,count=count,offset=offset,attempts=attempts,expected=expected))
args=[str(c[k]) for c in cases for k in ['timeout','count','offset','attempts']];runs=[]
for backend,command in [('native 1',['build/dns-udp-plan','--threads','1']),('native 4',['build/dns-udp-plan','--threads','4']),('Bun',[str(bun),'build/dns-udp-plan.js'])]:
    run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==[c['expected'] for c in cases],(backend,run)
    runs.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} timed-plan composition cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-udp-plan.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_udp_plan_check.py']
r=dict(scope=__doc__,cases=cases,runs=runs,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-udp-plan-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-udp-plan-result.json').write_text(json.dumps(r,indent=2)+'\n')
