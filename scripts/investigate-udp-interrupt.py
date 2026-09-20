"""Bounded investigation: TCP-style shutdown does not complete nonblocking UDP receive."""
import hashlib,json,os,select,socket,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';candidate=ROOT/'build/bend-udp-send-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-interrupt-probe-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-interrupt-probe.bend','-o',f'build/udp-interrupt-probe.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-interrupt-probe.c','-lpthread','-lm','-o','build/udp-interrupt-probe'],cwd=ROOT,check=True)
os_rows=[]
for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
    for connected in [False,True]:
        with socket.socket(af,socket.SOCK_DGRAM) as peer,socket.socket(af,socket.SOCK_DGRAM) as source:
            peer.bind((host,0));source.bind((host,0));source.setblocking(False)
            if connected:source.connect(peer.getsockname())
            row=dict(family=family,connected=connected)
            with socket.socket(fileno=os.dup(source.fileno())) as duplicate:
                try:duplicate.shutdown(socket.SHUT_RDWR);row['shutdown_error']=None
                except OSError as error:row['shutdown_error']=error.errno
            row['readable']=bool(select.select([source],[],[],0)[0])
            try:row['received']=repr(source.recvfrom(1024))
            except OSError as error:row['receive_error']=error.errno
            os_rows.append(row)
rows=[]
for backend,command in [('native 1',['build/udp-interrupt-probe','--threads','1']),('native 4',['build/udp-interrupt-probe','--threads','4']),('Bun',[str(bun),'build/udp-interrupt-probe.js'])]:
    for family in [4,6]:
        try:
            run=subprocess.run([*command,str(family),'1'],cwd=ROOT,capture_output=True,text=True,timeout=1)
            rows.append(dict(backend=backend,family=family,timeout=False,exit_code=run.returncode,stdout=run.stdout,stderr=run.stderr))
        except subprocess.TimeoutExpired as error:
            decode=lambda text: text.decode() if isinstance(text,bytes) else text or ''
            rows.append(dict(backend=backend,family=family,timeout=True,stdout=decode(error.stdout),stderr=decode(error.stderr)))
paths=['scripts/investigate-udp-interrupt.py','tests/udp-interrupt-probe.bend','packages/runtime/src/socket-interrupt.bend','patches/experimental/udp-bytes/udp_recv_bytes.c','patches/experimental/udp-bytes/udp_recv_bytes.js']
r=dict(scope=__doc__,os=os_rows,probe=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/udp-interrupt-investigation.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(rows,indent=2))
