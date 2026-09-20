"""Binary UDP receives, boundaries, truncation and non-consuming invalid limits."""
import hashlib,json,select,socket,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';candidate=ROOT/'build/bend-udp-family-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-bytes-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-bytes.bend','-o',f'build/udp-bytes.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-bytes.c','-lpthread','-lm','-o','build/udp-bytes'],cwd=ROOT,check=True)
cases=[(0,b''),(0,b'x'),(1,b''),(1,b'\xff'),(1,b'\0\xff'),(4,b'\0\xff\xc0\x80'),(4,b'\0\xff\xc0\x80!'),(1024,bytes(range(256))*4),(65535,bytes(range(256))*255+b'END'),(65536,b'kept\0\xff'),(4294967295,b'kept-again')]
rows=[]
for backend,cmd in [('native 1',['build/udp-bytes','--threads','1']),('native 4',['build/udp-bytes','--threads','4']),('Bun',[str(bun),'build/udp-bytes.js'])]:
    for family,af,host,prefix in [(4,socket.AF_INET,"127.0.0.1","4:2130706433:0:0:0"),(6,socket.AF_INET6,"::1","6:0:0:0:1")]:
        for maximum,data in cases:
            with socket.socket(af,socket.SOCK_DGRAM) as peer, socket.socket(af,socket.SOCK_DGRAM) as second:
                peer.bind((host,0));second.bind((host,0));limits=[maximum,65535] if maximum<=65535 else [maximum,65535,65535]
                p=subprocess.Popen([*cmd,str(family),*map(str,limits)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                try:
                    assert select.select([p.stdout],[],[],8)[0], 'bind timed out'
                    local=p.stdout.readline().strip().split(',');assert local[:5]==[str(family),'0','0','0','0'],local
                    peer.sendto(data,(host,int(local[5])))
                    second.sendto(b'\0\xff',(host,int(local[5])))
                    out,err=p.communicate(timeout=12)
                    bound=min(maximum,65535);expected=f'{prefix}:{peer.getsockname()[1]}:0:{int(len(data)>bound)}:'+''.join(str(b)+',' for b in data[:bound])
                    want=([expected] if maximum<=65535 else ['error:22',expected])+[f'{prefix}:{second.getsockname()[1]}:0:0:0,255,']
                    assert p.returncode==0 and not err and out.splitlines()==want,(backend,maximum,p.returncode,err,out[:300])
                    rows.append(dict(backend=backend,family=family,maximum=maximum,bytes=len(data),truncated=len(data)>bound))
                finally:
                    if p.poll() is None:p.kill();p.wait()
    print(f'{backend}: {len(cases)*2} binary UDP cases PASS',flush=True)
paths=['tests/udp-bytes.bend','tests/udp_bytes_check.py','scripts/prepare-udp-candidate.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/udp-bytes-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-bytes-result.json').write_text(json.dumps(r,indent=2)+'\n')
