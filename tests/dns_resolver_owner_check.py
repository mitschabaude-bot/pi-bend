"""Resolver replacement preserves a usable owner on seeding failure."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUN=Path.home()/'.bun/bin/bun'
CANDIDATE=ROOT/'build/bend-dns-refused-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','12','--stats',f'build/dns-resolver-owner-{suffix}-build.json','--',str(BUN),str(CANDIDATE/'main.ts'),'tests/dns-resolver-owner.bend','-o',f'build/dns-resolver-owner.{suffix}'],cwd=ROOT,check=True)
audit='\nstatic void __attribute__((destructor)) audit(void) { unsigned live=0; for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live; fprintf(stderr,"LIVE %u\\n",live); }\n'
(ROOT/'build/dns-resolver-owner-audit.c').write_text((ROOT/'build/dns-resolver-owner.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-resolver-owner-audit.c','-lpthread','-lm','-o','build/dns-resolver-owner'],cwd=ROOT,check=True)
want=['11,12,10,','unchanged','12,10,11,','updated','40,41,','updated','60,61,','60,61,']
checks=[]
for backend,command in [('native 1',['build/dns-resolver-owner','--threads','1']),('native 4',['build/dns-resolver-owner','--threads','4']),('Bun',[str(BUN),'build/dns-resolver-owner.js'])]:
    run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=20)
    assert run.returncode==0 and run.stdout.splitlines()==want and run.stderr==('LIVE 0\n' if backend!='Bun' else ''),(backend,run)
    checks.append(dict(backend=backend,trace=want,native_live_channels=0 if backend!='Bun' else None))
    print(backend+': resolver replacement PASS',flush=True)
paths=['packages/runtime/src/dns-tcp-resolver.bend','tests/dns-resolver-owner.bend','tests/dns_resolver_owner_check.py']
r=dict(scope=__doc__,checks=checks,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-resolver-owner-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-resolver-owner-result.json').write_text(json.dumps(r,indent=2)+'\n')
