"""Linux file/environment loading through real OS nameserver endpoint resolution."""
import errno
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=ROOT/'build/bend-profiles/edns-answer-teles/bend2'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','16','--stats',f'build/resolver-system-config-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-system-config.bend','-o',f'build/resolver-system-config.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-system-config.c','-lpthread','-lm','-o','build/resolver-system-config'],cwd=ROOT,check=True)
loopback=socket.if_nametoindex('lo')
def fields(values):return ''.join(f'{len(x)}:{x}' for x in values)
def settings(servers,options,invalid):
    return servers+['search:'+fields(['env.test']),'options:'+fields(options+['ndots:4']),'sort:','invalid:'+fields(invalid),'unknown:']
default=settings(['4:2130706433'],[],[])+['server:4:2130706433:53','none']
mixed_text='nameserver 127.0.0.1\nnameserver fe80::1%lo\nnameserver fe80::2%missing-if-xyz\nnameserver bad\nsearch file.test\noptions rotate edns0 trust-ad'
mixed=settings(['4:2130706433','6:4269801472,0,0,1:some:lo','6:4269801472,0,0,2:some:missing-if-xyz'],['rotate','edns0','trust-ad'],['bad'])+['server:4:2130706433:53',f'server:6:4269801472:0:0:1:{loopback}:53','server:6:4269801472:0:0:2:0:53','issue:2:missing-if-xyz:19','none']
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
    bad='options ndots:bad unknown-option'
    path=root/'bad-options';path.write_text(bad)
    cases.append(([str(path),'7',str(len(bad))],settings(['4:2130706433'],['ndots:bad','unknown-option'],[])+['server:4:2130706433:53','none','present','rejected','malformed:ndots:bad','unknown:unknown-option','END']))
    env={**os.environ,'LOCALDOMAIN':'env.test','RES_OPTIONS':'ndots:4'}
    for backend,command in [('native 1',['build/resolver-system-config','--threads','1']),('native 4',['build/resolver-system-config','--threads','4']),('Bun',[str(bun),'build/resolver-system-config.js'])]:
        for index,(args,expected) in enumerate(cases):
            want=list(expected)
            if any(line=='present' or line.startswith('unavailable:') for line in want) and 'rejected' not in want:
                rotating=any('6:rotate' in line for line in want if line.startswith('options:'))
                want += ['config:4,1,1,0,'+str(int(rotating))+':4321:17','288:1200,0:empty' if rotating else '256:none']+[line for line in expected if line.startswith('server:')]
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=20)
            assert run.returncode==0 and not run.stderr and run.stdout.splitlines()==want,(backend,index,run,want)
        checks.append(dict(backend=backend,cases=len(cases)))
        print(f'{backend}: {len(cases)} system file-to-resolver-configuration cases PASS',flush=True)
paths=['packages/runtime/src/resolver-system-config.bend','tests/resolver-system-config.bend','tests/resolver_system_config_check.py']
result=dict(scope=__doc__,checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-system-config-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-system-config-result.json').write_text(json.dumps(result,indent=2)+'\n')
