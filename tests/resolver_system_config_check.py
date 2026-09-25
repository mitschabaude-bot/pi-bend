"""Linux file/environment loading through real OS nameserver endpoint resolution."""
import argparse
import re
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
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN);args=parser.parse_args()
compiler=args.candidate.resolve()
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-system-config-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-system-config.bend','-o',f'build/resolver-system-config.{suffix}'],cwd=ROOT,check=True)
audit='\nstatic void __attribute__((destructor)) audit(void) { unsigned live=0; for(u32 i=0;i<chan_len;i++) live+=chan_rows[i].live; fprintf(stderr,"LIVE %u\\n",live); }\n'
(ROOT/'build/resolver-system-config-audit.c').write_text((ROOT/'build/resolver-system-config.c').read_text()+audit)
(ROOT/'build/resolver-system-config-audit.js').write_text('process.on("exit",()=>console.error(`LIVE ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+(ROOT/'build/resolver-system-config.js').read_text())
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-system-config-audit.c','-lpthread','-lm','-o','build/resolver-system-config'],cwd=ROOT,check=True)
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
    for count in [1,2,3,4]:
        text=''.join(f'nameserver 127.0.0.{i+1}\n' for i in range(count))+'options timeout:2 attempts:3 rotate edns0 trust-ad use-vc'
        path=root/f'transport-{count}';path.write_text(text)
        want=settings([f'4:{2130706433+i}' for i in range(count)],['timeout:2','attempts:3','rotate','edns0','trust-ad','use-vc'],[])+[f'server:4:{2130706433+i}:53' for i in range(count)]+['none','present']
        if count==4:want+=['transport-rejected:too-many']
        cases.append(([str(path),'7',str(len(text))],want))
    env={**os.environ,'LOCALDOMAIN':'env.test','RES_OPTIONS':'ndots:4'}
    for backend,command in [('native 1',['build/resolver-system-config','--threads','1']),('native 4',['build/resolver-system-config','--threads','4']),('Bun',[str(bun),'build/resolver-system-config-audit.js'])]:
        for index,(args,expected) in enumerate(cases):
            want=list(expected)
            if any(line=='present' or line.startswith('unavailable:') for line in want) and 'rejected' not in want and not any(line.startswith('transport-rejected:') for line in want):
                rotating=any('6:rotate' in line for line in want if line.startswith('options:'))
                want += ['config:4,1,1,0,'+str(int(rotating))+':4321:17','288:1200,0:empty' if rotating else '256:none']+[line for line in expected if line.startswith('server:')]
                servers=[line for line in expected if line.startswith('server:')]
                configured='transport-' in args[0]
                timeout,attempts=(2,3) if configured else (5,2)
                budgets=[max(1,timeout if i==0 else timeout*(2**i)//len(servers)) for i in range(len(servers))]
                flags=','.join(map(str,[int(rotating),int(rotating),0,0,0,0,int(configured),int(rotating),0]))
                want += [f'transport:{timeout}:{attempts}:'+''.join(f'{n},' for n in budgets)+':,'+flags,'owner:closed']
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=20)
            assert run.returncode==0 and run.stderr==('LIVE 0 0\n' if backend=='Bun' else 'LIVE 0\n') and run.stdout.splitlines()==want,(backend,index,run,want)
            checks.append(dict(backend=backend,index=index,arguments=args,output=want,audit=run.stderr.strip()))
        print(f'{backend}: {len(cases)} system file-to-resolver-configuration cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/resolver-system-config.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/resolver_system_config_check.py']
result=dict(scope=__doc__,checks=checks,compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-system-config-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-system-config-result.json').write_text(json.dumps(result,indent=2)+'\n')
