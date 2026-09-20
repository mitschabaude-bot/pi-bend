"""Resolver replacement preserves a usable owner on seeding failure."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUN=Path.home()/'.bun/bin/bun'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=ROOT/'build/bend-dns-refused-candidate')
CANDIDATE=parser.parse_args().candidate.resolve()
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-native-resolver-owner-{suffix}-build.json','--',str(BUN),str(CANDIDATE/'main.ts'),'tests/dns-native-resolver-owner.bend','-o',f'build/dns-native-resolver-owner.{suffix}'],cwd=ROOT,check=True)
audit='\nstatic void __attribute__((destructor)) audit(void) { unsigned live=0; for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live; fprintf(stderr,"LIVE %u\\n",live); }\n'
(ROOT/'build/dns-native-resolver-owner-audit.c').write_text((ROOT/'build/dns-native-resolver-owner.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-native-resolver-owner-audit.c','-lpthread','-lm','-o','build/dns-native-resolver-owner'],cwd=ROOT,check=True)
(ROOT/'build/dns-native-resolver-owner-audit.js').write_text('process.on("exit",()=>console.error(`LIVE ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+(ROOT/'build/dns-native-resolver-owner.js').read_text())
want=['11@second3=1;12@third3=2;10@first=2;','256:plain','unchanged','12@third3=2;10@first=2;11@second3=1;','256:plain','updated','40@first=2;41@second2=2;','288:edns','updated','60@first=2;61@second2=2;','256:plain','60@first=2;61@second2=2;','256:plain']
checks=[]
for backend,command in [('native 1',['build/dns-native-resolver-owner','--threads','1']),('native 4',['build/dns-native-resolver-owner','--threads','4']),('Bun',[str(BUN),'build/dns-native-resolver-owner-audit.js'])]:
    run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=20)
    assert run.returncode==0 and run.stdout.splitlines()==want and run.stderr==('LIVE 0\n' if backend!='Bun' else 'LIVE 0 0\n'),(backend,run)
    checks.append(dict(backend=backend,trace=want,native_live_channels=0 if backend!='Bun' else None, audit=run.stderr.strip()))
    print(backend+': resolver replacement PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-native-resolver-owner.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_native_resolver_owner_check.py']
r=dict(scope=__doc__,checks=checks,compiler_sha256={p:hashlib.sha256((CANDIDATE/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-native-resolver-owner-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-native-resolver-owner-result.json').write_text(json.dumps(r,indent=2)+'\n')
