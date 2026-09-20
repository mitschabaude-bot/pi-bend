"""Exhaust the parsed timeout/position domain against the pinned glibc formula.

This executes compiled Bend arithmetic. Generic duration laws remain separate;
Python supplies only the external reference formula and process orchestration.
"""
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun'
compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-udp-timeout-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/dns-udp-timeout.bend','-o',f'build/dns-udp-timeout.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-udp-timeout.c','-lpthread','-lm','-o','build/dns-udp-timeout'],cwd=ROOT,check=True)
cases=[]
for count in [1,2,3]:
    for index in range(count):
        code=0 if index==0 else 1 if count==2 else 2 if index==1 else 3
        for timeout in [*range(31),31,32,4294967295]:
            scaled=timeout<<index
            expected=str(max(1,scaled if index==0 else scaled//count)) if timeout<=30 else f'invalid:{timeout}'
            cases.append(dict(count=count,index=index,position=code,timeout=timeout,expected=expected))
args=[arg for case in cases for arg in [str(case['timeout']),str(case['position'])]]
runs=[]
for backend,command in [('native 1',['build/dns-udp-timeout','--threads','1']),('native 4',['build/dns-udp-timeout','--threads','4']),('Bun',[str(bun),'build/dns-udp-timeout.js'])]:
    run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==[c['expected'] for c in cases],(backend,run)
    runs.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} timeout formula cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-udp-timeout.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_udp_timeout_check.py']
r=dict(scope=__doc__,references=['https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_send.c','https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/resolv.h','https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/bits/types/res_state.h'],cases=cases,runs=runs,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-udp-timeout-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-udp-timeout-result.json').write_text(json.dumps(r,indent=2)+'\n')
