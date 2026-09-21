"""Hook adapter results, forwarded inputs and caller callback lifetimes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from channel_audit import instrument

ROOT=Path(__file__).resolve().parents[1]
compiler=ROOT/'build/bend-profiles/dns-transport-teles/bend2/main.ts'
parser=argparse.ArgumentParser()
parser.add_argument('--source',default='tests/provider-hook-map.bend')
parser.add_argument('--prefix',default='build/provider-hook-map')
config=parser.parse_args()
source=ROOT/config.source
prefix=ROOT/config.prefix
pending=[source]
closure=set()
while pending:
    path=pending.pop().resolve()
    if path in closure:
        continue
    closure.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(closure)}
for backend in ('c','js'):
    with Path(str(prefix)+'-'+backend+'.log').open('w') as log:
        subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib','4','--stats',str(prefix)+'-'+backend+'-build.json','--',str(compiler),str(source),'-o',str(prefix)+'.'+backend],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
Path(str(prefix)+'-audit.c').write_text(Path(str(prefix)+'.c').read_text()+r'''
static void __attribute__((destructor)) hook_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u\n",channels,io_park.head!=NULL);
}
''')
Path(str(prefix)+'-audit.js').write_text(instrument(Path(str(prefix)+'.js').read_text()))
runs=[]
for suffix in ('','-audit'):
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',str(prefix)+suffix+'.c','-lpthread','-lm','-o',str(prefix)+suffix],check=True,timeout=180)
    for backend,command in [('native-1',[str(prefix)+suffix,'--threads','1']),('native-4',[str(prefix)+suffix,'--threads','4']),('bun',[str(Path.home()/'.bun/bin/bun'),str(prefix)+suffix+'.js'])]:
        result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,check=True,timeout=20)
        assert result.stdout=='PASS twenty hook adapter outcomes and borrowed callback lifetimes\n',(backend,result)
        assert result.stderr==(('AUDIT 0 0 0\n' if backend=='bun' else 'AUDIT 0 0\n') if suffix else ''),(backend,result)
        runs.append(dict(backend=backend,audited=bool(suffix),cases=20,passed=True))
        print(backend,suffix or 'plain','20 hook adapter cases PASS',flush=True)
assert sources=={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources}
record=dict(fixture=config.source,scope='Four hook-presence combinations and five outcomes, two calls per mapped hook, disposal followed by successful calls to both original hooks. Payload/model/status/header forwarding, absent replacement versus explicit null, typed error embedding and exact call counts. Six backend/audit combinations; finite ownership evidence, not a universal IO proof.',sources=sources,harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),audit_helper_sha256=hashlib.sha256((ROOT/'tests/channel_audit.py').read_bytes()).hexdigest(),programs={str(prefix)+s:hashlib.sha256(Path(str(prefix)+s).read_bytes()).hexdigest() for s in ('','.c','.js','-audit','-audit.c','-audit.js')},runs=runs)
Path(str(prefix)+'-results.json').write_text(json.dumps(record,indent=2)+'\n')
