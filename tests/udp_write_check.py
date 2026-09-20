"""Owned UDP sends: cancellation/release before transmission, completion, validation and stale capabilities."""
import argparse
import errno,hashlib,json,select,socket,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path,nargs='?',default=ROOT/'build/bend-udp-write-candidate')
candidate=parser.parse_args().candidate.resolve()
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-write-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-write.bend','-o',f'build/udp-write.{suffix}'],cwd=ROOT,check=True)
audit='\nstatic void __attribute__((destructor)) udp_write_audit(void) {\n  unsigned rows=0, channels=0, sockets=0;\n  for(u32 i=0;i<udp_write_len;i++) rows+=udp_write_rows[i].live;\n  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;\n  for(int fd=0;fd<4096;fd++){int type; socklen_t n=sizeof(type); if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}\n  fprintf(stderr,"AUDIT %u %u %u %u\\n",rows,channels,io_park.head!=NULL,sockets);\n}\n'
(ROOT/'build/udp-write-audit.c').write_text((ROOT/'build/udp-write.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-write-audit.c','-lpthread','-lm','-o','build/udp-write'],cwd=ROOT,check=True)
rows=[]
for backend,cmd in [('native 1',['build/udp-write','--threads','1']),('native 4',['build/udp-write','--threads','4']),('Bun',[str(bun),'build/udp-write.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        cases=[(n,'ok',None) for n in [0,1,256,65507]]+[(65536,'ok',errno.EMSGSIZE),(256,'byte',errno.EINVAL)]+[(n,mode,'cancelled') for n in [0,256,65536] for mode in ['cancel','release']]
        for size,mode,error in cases:
            with socket.socket(af,socket.SOCK_DGRAM) as peer:
                peer.bind((host,0));peer.settimeout(5)
                r=subprocess.run([*cmd,str(family),str(peer.getsockname()[1]),str(size),mode],cwd=ROOT,capture_output=True,text=True,timeout=15)
                assert r.returncode==0 and r.stderr==('' if backend=='Bun' else 'AUDIT 0 0 0 0\n') and r.stdout.splitlines()==(['ok','ok'] if error is None else ['cancelled' if error=='cancelled' else f'error:{error}','ok']),(backend,family,size,mode,r)
                first_sender=None
                if error is None:
                    data,first_sender=peer.recvfrom(65536);assert data==bytes(i%256 for i in range(size)),(backend,size,len(data))
                marker,sender=peer.recvfrom(65536);assert marker==b'\x11\0\xff' and (first_sender is None or first_sender==sender),(backend,marker)
                assert not select.select([peer],[],[],0)[0],'unexpected or partial datagram'
                rows.append(dict(backend=backend,family=family,size=size,mode=mode,error=error))
    print(f'{backend}: 24 owned UDP send cases PASS',flush=True)
paths=['tests/udp-write.bend','tests/udp_write_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/udp-write-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-write-result.json').write_text(json.dumps(r,indent=2)+'\n')
