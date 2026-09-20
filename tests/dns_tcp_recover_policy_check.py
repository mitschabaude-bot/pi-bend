"""Reset policy guards: operation, cleanup, abort and platform errno."""
import errno
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1]).resolve();bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-tcp-recover-policy-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-tcp-recover-policy.bend','-o',f'build/dns-tcp-recover-policy.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-tcp-recover-policy.c','-lpthread','-lm','-o','build/dns-tcp-recover-policy'],cwd=ROOT,check=True)
for backend,command in [('native 1',['build/dns-tcp-recover-policy','--threads','1']),('native 4',['build/dns-tcp-recover-policy','--threads','4']),('Bun',[str(bun),'build/dns-tcp-recover-policy.js'])]:
    run=subprocess.run([*command,str(errno.ECONNRESET)],cwd=ROOT,capture_output=True,text=True,timeout=15)
    assert run.returncode==0 and run.stdout=='PASS reset policy\n' and not run.stderr,(backend,run)
    print(backend+': 10 reset policy cases PASS',flush=True)
paths=['packages/runtime/src/dns-tcp-recover.bend','tests/dns-tcp-recover-policy.bend','tests/dns_tcp_recover_policy_check.py']
r=dict(scope=__doc__,cases_per_backend=10,backends=['native 1','native 4','Bun'],sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-tcp-recover-policy-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-tcp-recover-policy-result.json').write_text(json.dumps(r,indent=2)+'\n')
