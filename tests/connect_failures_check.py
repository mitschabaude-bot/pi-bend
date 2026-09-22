"""Exercise owned-connect refusal and invalid-port failure paths on loopback."""
import errno
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve();bun=Path.home()/'.bun/bin/bun'
for suffix in ['c','js']:
    subprocess.run([str(bun),str(candidate/'main.ts'),'tests/connect-failures.bend','-o',f'build/connect-failures.{suffix}'],cwd=ROOT,check=True,timeout=60)
subprocess.run(['clang','-fbracket-depth=2048','-std=c11','-O1','build/connect-failures.c','-lpthread','-lm','-o','build/connect-failures'],cwd=ROOT,check=True,timeout=60)
rows=[]
for label,command in [('native 1',['build/connect-failures','--threads','1']),('native 4',['build/connect-failures','--threads','4']),('Bun',[str(bun),'build/connect-failures.js'])]:
    for family,host,number in [(socket.AF_INET,'127.0.0.1',4),(socket.AF_INET6,'::1',6)]:
        with socket.socket(family,socket.SOCK_STREAM) as closed:
            closed.bind((host,0))
            for port,expected in [(closed.getsockname()[1],errno.ECONNREFUSED),(65536,errno.EINVAL),(4294967295,errno.EINVAL)]:
                result=subprocess.run([*command,str(number),str(port)],cwd=ROOT,capture_output=True,text=True,timeout=15)
                assert result.returncode==0 and not result.stderr,(label,result)
                assert result.stdout.splitlines()==[f'error:{expected}']*32,(label,number,port,result.stdout)
                rows.append({'backend':label,'family':number,'port':port,'expected_errno':expected,'repetitions':32})
    print(label+': IPv4/IPv6 refusal and port-range failures PASS',flush=True)
record={'scope':__doc__,'cases':rows,'production_sha256':{name:hashlib.sha256((candidate/'effs'/name).read_bytes()).hexdigest() for name in ['connect.c','connect.js']}}
(ROOT/'build/connect-failures-result.json').write_text(json.dumps(record,indent=2)+'\n')
