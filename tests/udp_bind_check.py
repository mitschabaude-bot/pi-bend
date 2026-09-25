"""UDP family/port validation, occupied ports, and IPv6-only wildcard binding."""
import argparse
import errno,hashlib,json,socket,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
candidate=parser.parse_args().candidate.resolve()
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-bind-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-bind.bend','-o',f'build/udp-bind.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-bind.c','-lpthread','-lm','-o','build/udp-bind'],cwd=ROOT,check=True)
rows=[]
for backend,cmd in [('native 1',['build/udp-bind','--threads','1']),('native 4',['build/udp-bind','--threads','4']),('Bun',[str(bun),'build/udp-bind.js'])]:
    def check(family,port,error=None):
        r=subprocess.run([*cmd,str(family),str(port)],cwd=ROOT,capture_output=True,text=True,timeout=8)
        assert r.returncode==0 and not r.stderr,(backend,r)
        if error is not None:assert r.stdout==f'error:{error}\n',(backend,r)
        else:
            fields=list(map(int,r.stdout.strip().split(',')))
            assert fields[:5]==[family,0,0,0,0] and fields[6]==0 and 0<fields[5]<=65535 and (port==0 or fields[5]==port),(backend,r)
        rows.append(dict(backend=backend,family=family,port=port,error=error))
    for family,port in [(0,0),(5,0),(4294967295,0),(4,65536),(6,65536),(4,4294967295),(6,4294967295)]:check(family,port,errno.EINVAL)
    for family,af,host in [(4,socket.AF_INET,'0.0.0.0'),(6,socket.AF_INET6,'::')]:
        check(family,0)
        with socket.socket(af,socket.SOCK_DGRAM) as occupied:
            if family==6:occupied.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
            occupied.bind((host,0));check(family,occupied.getsockname()[1],errno.EADDRINUSE)
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as occupied:
        occupied.bind(('0.0.0.0',0));check(6,occupied.getsockname()[1])
    print(f'{backend}: 12 UDP bind cases PASS',flush=True)
paths=['tests/udp-bind.bend','tests/udp_bind_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/udp-bind-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-bind-result.json').write_text(json.dumps(r,indent=2)+'\n')
