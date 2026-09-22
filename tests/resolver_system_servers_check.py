"""Linux file/environment loading through real OS nameserver endpoint resolution."""
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats',f'build/resolver-system-servers-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-system-servers.bend','-o',f'build/resolver-system-servers.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-system-servers.c','-lpthread','-lm','-o','build/resolver-system-servers'],cwd=ROOT,check=True)
loopback=socket.if_nametoindex('lo')
def fields(values):return ''.join(f'{len(x)}:{x}' for x in values)
def settings(servers,options,invalid):
    return servers+['search:'+fields(['env.test']),'options:'+fields(options+['ndots:4']),'sort:','invalid:'+fields(invalid),'unknown:']
default=settings(['4:2130706433'],[],[])+['server:4:2130706433:53','none']
mixed_text='nameserver 127.0.0.1\nnameserver fe80::1%lo\nnameserver fe80::2%missing-if-xyz\nnameserver bad\nsearch file.test\noptions rotate'
mixed=settings(['4:2130706433','6:4269801472,0,0,1:some:lo','6:4269801472,0,0,2:some:missing-if-xyz'],['rotate'],['bad'])+['server:4:2130706433:53',f'server:6:4269801472:0:0:1:{loopback}:53','server:6:4269801472:0:0:2:0:53','issue:2:missing-if-xyz:19','none']
checks=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-resolver-endpoints-') as temp:
    root=Path(temp);cases=[]
    for i,(text,want) in enumerate([('',default),(mixed_text,mixed),('nameserver bad',settings(['4:2130706433'],[],['bad'])+['server:4:2130706433:53','none'])]):
        path=root/str(i);path.write_text(text)
        for chunk in [1,7,4096]:
            cases.append(([str(path),str(chunk),str(len(text.encode()))],want+['present']))
            if text:cases.append(([str(path),str(chunk),str(len(text.encode())-1)],['large']))
    for chunk in [1,7,4096]:
        cases.append(([str(root/'missing'),str(chunk),'0'],default+[f'unavailable:{errno.ENOENT}']))
        cases.append(([str(root),str(chunk),'4096'],[f'read:{errno.EISDIR}']))
    cases.append(([str(root/'missing'),'0','0'],['size']))
    env={**os.environ,'LOCALDOMAIN':'env.test','RES_OPTIONS':'ndots:4'}
    for backend,command in [('native 1',['build/resolver-system-servers','--threads','1']),('native 4',['build/resolver-system-servers','--threads','4']),('Bun',[str(bun),'build/resolver-system-servers.js'])]:
        for index,(args,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=20)
            assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,run,want)
        checks.append(dict(backend=backend,cases=len(cases)))
        print(f'{backend}: {len(cases)} system file-to-endpoint cases PASS',flush=True)
paths=['packages/runtime/src/dns-resolver.bend','tests/resolver-system-servers.bend','tests/resolver_system_servers_check.py']
result=dict(scope=__doc__,checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-system-servers-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-system-servers-result.json').write_text(json.dumps(result,indent=2)+'\n')
