"""Abortable UDP receives preserve reasons and retire deadline/observer resources."""
import hashlib,json,select,socket,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';candidate=ROOT/'build/bend-udp-cancel-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/abortable-datagram-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/abortable-datagram.bend','-o',f'build/abortable-datagram.{suffix}'],cwd=ROOT,check=True)
audit='''
static void __attribute__((destructor)) udp_audit(void) {
  unsigned rows=0, channels=0, sockets=0, timers=0;
  for(u32 i=0;i<udp_read_len;i++) rows+=udp_read_rows[i].live;
  for(u32 i=0;i<timer_len;i++) timers+=timer_rows[i].live;
  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){ int type; socklen_t n=sizeof(type); if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0) sockets++; }
  fprintf(stderr,"AUDIT %u %u %u %u %u\\n",rows,channels,io_park.head!=NULL,sockets,timers);
}
'''
(ROOT/'build/abortable-datagram-audit.c').write_text((ROOT/'build/abortable-datagram.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/abortable-datagram-audit.c','-lpthread','-lm','-o','build/abortable-datagram'],cwd=ROOT,check=True)
def line(stream):
    data=b'';until=time.monotonic()+10
    while not data.endswith(b'\n'):
        assert select.select([stream],[],[],max(0,until-time.monotonic()))[0],'fixture timed out'
        byte=stream.read(1);assert byte,'early exit';data+=byte
    return data.decode().strip()
rows=[]
for backend,cmd in [('native 1',['build/abortable-datagram','--threads','1']),('native 4',['build/abortable-datagram','--threads','4']),('Bun',[str(bun),'build/abortable-datagram.js'])]:
    for family,af,host,prefix in [(4,socket.AF_INET,'127.0.0.1','4:2130706433:0:0:0'),(6,socket.AF_INET6,'::1','6:0:0:0:1')]:
        for mode in ['pre','custom','default','deadline','packet','empty','short','invalid']:
            for count in [1,10]:
                with socket.socket(af,socket.SOCK_DGRAM) as peer:
                    peer.bind((host,0))
                    p=subprocess.Popen([*cmd,str(family),mode,str(count)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
                    try:
                        local=line(p.stdout).split(',');assert local[:5]==[str(family),'0','0','0','0'],local
                        if mode in ['packet','empty','short']:
                            for _ in range(count):peer.sendto(b'' if mode=='empty' else b'\0\xff', (host,int(local[5])))
                        first={'pre':'abort:parent:stop','custom':'abort:parent:stop','default':'abort:default','deadline':'abort:expiry','packet':'packet:0:0,255,','empty':'packet:0:','short':'packet:1:0,','invalid':'error:22'}[mode]
                        scope={'pre':'parent:stop','custom':'parent:stop','default':'default','deadline':'expiry'}.get(mode,'none')
                        for _ in range(count):
                            assert line(p.stdout)==first,(backend,family,mode)
                            assert line(p.stdout)=='scope:'+scope,(backend,family,mode)
                        assert line(p.stdout)=='ready' 
                        peer.sendto(b'\0\xff', (host,int(local[5])))
                        out,err=p.communicate(timeout=8)
                        assert p.returncode==0 and out.decode().splitlines()==[f'{prefix}:{peer.getsockname()[1]}:0:0:0,255,'] and err==(b'' if backend=='Bun' else b'AUDIT 0 0 0 0 0\n'),(backend,family,mode,count,p.returncode,out,err)
                        rows.append(dict(backend=backend,family=family,mode=mode,iterations=count,native_audit=err.decode().strip()))
                    finally:
                        if p.poll() is None:p.kill();p.wait()
    print(f'{backend}: 32 abortable UDP scenarios PASS',flush=True)
paths=['packages/runtime/src/abortable-datagram.bend','packages/runtime/src/abort-outcome.bend','tests/abortable-datagram.bend','tests/abortable_datagram_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/abortable-datagram-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/abortable-datagram-result.json').write_text(json.dumps(r,indent=2)+'\n')
