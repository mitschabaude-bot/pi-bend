"""Configured order survives seeded rotation, in pure and owned APIs."""
import hashlib
import itertools
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUN = Path.home()/'.bun/bin/bun'
COMPILER = TOOLCHAIN
for suffix in ['c', 'js']:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'build/dns-server-position-{suffix}-build.json', '--', str(BUN), str(COMPILER/'main.ts'), 'tests/dns-server-position.bend', '-o', f'build/dns-server-position.{suffix}'], cwd=ROOT, check=True)
audit = '\nstatic void __attribute__((destructor)) audit(void) { unsigned live=0; for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live; fprintf(stderr,"LIVE %u\\n",live); }\n'
(ROOT/'build/dns-server-position-audit.c').write_text((ROOT/'build/dns-server-position.c').read_text()+audit)
subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', 'build/dns-server-position-audit.c', '-lpthread', '-lm', '-o', 'build/dns-server-position'], cwd=ROOT, check=True)
flags = [''.join(bits) for bits in itertools.product('01', repeat=6)]
cases = [(values, offset, switches) for values in [[], [7], [0,1], [0,1,2], [9,9,7]] for offset in [0,1,2,3,7,257,2147483648,4294967295] for switches in flags]
cases += [(list(range(8192)), 4294967295, '001011'), ([0,1,2], 2, '1'*10002), ([0,1,2], 1, '')]

def expected(values, offset, switches):
    at = offset % len(values) if values else 0
    current = values[at:]+values[:at]
    result = []
    for flag in switches:
        result.append(''.join(str(v)+',' for v in (current if flag=='1' else values)))
        if flag=='1' and current: current = current[1:]+current[:1]
    return result+result

checks = []
for backend, command in [('native 1', ['build/dns-server-position','--threads','1']), ('native 4', ['build/dns-server-position','--threads','4']), ('Bun', [str(BUN),'build/dns-server-position.js'])]:
    for start in range(0,len(cases),32):
        batch = cases[start:start+32]
        args = [arg for values,offset,switches in batch for arg in [','.join(map(str,values)),str(offset),switches]]
        wanted = [line for case in batch for line in expected(*case)]
        run = subprocess.run([*command,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and run.stdout.splitlines()==wanted and run.stderr==('LIVE 0\n' if backend.startswith('native') else ''), (backend,start,run.returncode,run.stderr,run.stdout[:300],[line[:80] for line in wanted[:3]])
    checks.append(dict(backend=backend,sequences=len(cases),api_checks=2*len(cases),native_live_channels=0 if backend.startswith('native') else None))
    print(backend+': '+str(len(cases))+' seeded sequences PASS',flush=True)
paths = ['packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns-server-position.bend','tests/dns_server_position_check.py']
record = dict(scope=__doc__,checks=checks,case_digest=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-server-position-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-server-position-result.json').write_text(json.dumps(record,indent=2)+'\n')
