"""Compiled DNS header policy against the glibc 2.39 single-query decision order."""
import hashlib,itertools,json,re,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-udp-policy-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/dns-udp-policy.bend','-o',f'build/dns-udp-policy.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-udp-policy.c','-lpthread','-lm','-o','build/dns-udp-policy'],cwd=ROOT,check=True)
cases=[]
for code,aa,ra,tc,answers,additional,ignore,other in itertools.product(range(16),[0,1],[0,1],[0,1],[0,65535],[0,65535],[0,1],[0,65535]):
    flags=code | (aa<<10) | (ra<<7) | (tc<<9) | (0xF970 if other else 0)
    if code in [2,4,5]:expected={2:'servfail',4:'notimp',5:'refused'}[code]
    elif code==0 and answers==0 and not aa and not ra and additional==0:expected='empty'
    elif tc and not ignore:expected='tcp'
    else:expected='accept'
    cases.append(dict(flags=flags,answers=answers,additional=additional,ignore=ignore,other=other,expected=expected))
args=[str(c[k]) for c in cases for k in ['flags','answers','additional','ignore','other']];runs=[]
for backend,command in [('native 1',['build/dns-udp-policy','--threads','1']),('native 4',['build/dns-udp-policy','--threads','4']),('Bun',[str(bun),'build/dns-udp-policy.js'])]:
    run=subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==[c['expected'] for c in cases],(backend,run)
    runs.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} header-policy cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-udp-policy.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_udp_policy_check.py']
r=dict(scope=__doc__,case_count=len(cases),reference='https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_send.c',coverage='all 16 low RCODEs, AA/RA/TC bits, zero/max answer and additional counts, ignore-TC, irrelevant header fields/bits',runs=runs,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-udp-policy-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-udp-policy-result.json').write_text(json.dumps(r,indent=2)+'\n')
