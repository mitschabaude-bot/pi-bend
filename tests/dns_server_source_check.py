"""Concurrent borrowed server selectors: complete orders, atomic steps, teardown."""
from collections import Counter
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-server-source-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/dns-server-source.bend','-o',f'build/dns-server-source.{suffix}'],cwd=ROOT,check=True)
# Exit-only native instrumentation in a disposable generated file.
audit='''\nstatic void __attribute__((destructor)) source_audit(void) {
  unsigned live=0;
  for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live;
  fprintf(stderr,"SOURCE_CHANNELS %u\\n",live);
}\n'''
(ROOT/'build/dns-server-source-audit.c').write_text((ROOT/'build/dns-server-source.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-server-source-audit.c','-lpthread','-lm','-o','build/dns-server-source'],cwd=ROOT,check=True)
def render(values):return ''.join(str(v)+',' for v in values)
rows=[]
for backend,command in [('native 1',['build/dns-server-source','--threads','1']),('native 4',['build/dns-server-source','--threads','4']),('Bun',[str(bun),'build/dns-server-source.js'])]:
    for values in [[],[7],[0,1],[0,1,2],[9,9,7]]:
        for enabled in [False,True]:
            for count in [0,1,2,3,17,97,256]:
                current=values[:];expected=[]
                for _ in range(count):
                    expected.append(render(current if enabled else values))
                    if enabled and current:current=current[1:]+current[:1]
                following=render(current if enabled else values)
                run=subprocess.run([*command,','.join(map(str,values)),str(int(enabled)),'x'*count],cwd=ROOT,capture_output=True,text=True,timeout=20)
                lines=run.stdout.splitlines();error='SOURCE_CHANNELS 0\n' if backend.startswith('native') else ''
                assert run.returncode==0 and run.stderr==error and len(lines)==count+1,(backend,values,enabled,count,run)
                assert Counter(lines[:-1])==Counter(expected) and lines[-1]=='next:'+following,(backend,values,enabled,count,lines)
                rows.append(dict(backend=backend,servers=values,enabled=enabled,tasks=count,next_order=following,live_channels=0 if error else None))
    print(backend+': 70 concurrent selector cases PASS',flush=True)
paths=['packages/runtime/src/dns-transport.bend','packages/runtime/src/dns-transport.bend','tests/dns-server-source.bend','tests/dns_server_source_check.py']
r=dict(scope=__doc__,cases=rows,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/dns-server-source-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/dns-server-source-result.json').write_text(json.dumps(r,indent=2)+'\n')
