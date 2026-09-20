"""DNS ID decoding: full octet coverage, boundaries and typed source errors."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1]).resolve();bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
    subprocess.run([str(bun),str(candidate/'main.ts'),'tests/dns-id.bend','-o',f'build/dns-id.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-O1','build/dns-id.c','-lpthread','-lm','-o','build/dns-id'],cwd=ROOT,check=True)
# Independently decode network bytes, exercising every octet in both positions.
pairs=sorted({(a,b) for a in range(256) for b in [0,1,127,128,255]}|{(a,b) for a in [0,1,127,128,255] for b in range(256)})
inputs=[f'{a},{b}' for a,b in pairs]
expected=['source:11:not ready',*[str(int.from_bytes(bytes(pair),'big')) for pair in pairs]]
for values in [[],[0],[255],[0,0,0],[256,0],[0,256],[4294967295,0],[0,4294967295]]:
    inputs.append(','.join(map(str,values)));expected.append('invalid')
rows=[]
for label,command in [('native 1',['build/dns-id','--threads','1']),('native 4',['build/dns-id','--threads','4']),('Bun',[str(bun),'build/dns-id.js'])]:
    run=subprocess.run([*command,*inputs],cwd=ROOT,capture_output=True,text=True,timeout=30)
    assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==expected,(label,run)
    rows.append(dict(backend=label,cases=len(expected)));print(label+': DNS ID decode PASS',flush=True)
paths=['packages/runtime/src/dns-id.bend','tests/dns-id.bend','tests/dns_id_check.py','build/dns-id','build/dns-id.js']
(ROOT/'build/dns-id-result.json').write_text(json.dumps(dict(cases=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}),indent=2)+'\n')
