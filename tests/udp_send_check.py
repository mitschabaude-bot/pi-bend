"""Binary UDP sends preserve packets and reject invalid inputs before transmission."""
import argparse
import errno,hashlib,json,select,socket,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
candidate=parser.parse_args().candidate.resolve()
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-send-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-send.bend','-o',f'build/udp-send.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-send.c','-lpthread','-lm','-o','build/udp-send'],cwd=ROOT,check=True)
rows=[]
for backend,cmd in [('native 1',['build/udp-send','--threads','1']),('native 4',['build/udp-send','--threads','4']),('Bun',[str(bun),'build/udp-send.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        cases=[(n,'ok',None) for n in [0,1,256,4096,65507]]+[(65535,'ok',errno.EMSGSIZE),(65536,'ok',errno.EMSGSIZE)]+[(n,'byte',errno.EINVAL) for n in [0,255,65536]]+[(1,m,errno.EINVAL) for m in ['family','zero-port','large-port']]
        cases += [(65508,'ok',errno.EMSGSIZE)] if family==4 else [(65508,'ok',None),(65527,'ok',None),(65528,'ok',errno.EMSGSIZE)]
        if family==4:cases += [(1,m,errno.EINVAL) for m in ['word','scope']]
        for size,mode,error in cases:
            with socket.socket(af,socket.SOCK_DGRAM) as peer:
                peer.bind((host,0));peer.settimeout(5)
                r=subprocess.run([*cmd,str(family),str(peer.getsockname()[1]),str(size),mode],cwd=ROOT,capture_output=True,text=True,timeout=15)
                assert r.returncode==0 and not r.stderr and r.stdout.splitlines()==(['ok','ok'] if error is None else [f'error:{error}','ok']),(backend,family,size,mode,r)
                first_sender=None
                if error is None:
                    data,first_sender=peer.recvfrom(65536);assert data==bytes(i%256 for i in range(size)),(backend,size,len(data))
                marker,sender=peer.recvfrom(65536);assert marker==b'\x11\0\xff' and (first_sender is None or first_sender==sender),(backend,marker)
                assert not select.select([peer],[],[],0)[0],'unexpected or partial datagram'
                rows.append(dict(backend=backend,family=family,size=size,mode=mode,error=error))
    print(f'{backend}: 32 binary UDP send cases PASS',flush=True)
paths=['tests/udp-send.bend','tests/udp_send_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/udp-send-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-send-result.json').write_text(json.dumps(r,indent=2)+'\n')
