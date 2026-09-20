"""Racing packet arrival and cancellation must preserve exactly one packet and completion."""
import hashlib,json,select,socket,subprocess,time,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';candidate=(ROOT/sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'build/bend-udp-cancel-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-read-race-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-read-race.bend','-o',f'build/udp-read-race.{suffix}'],cwd=ROOT,check=True)
audit='''
static void __attribute__((destructor)) udp_audit(void) {
  unsigned rows=0, channels=0, sockets=0;
  for(u32 i=0;i<udp_read_len;i++) rows+=udp_read_rows[i].live;
  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){ int type; socklen_t n=sizeof(type); if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0) sockets++; }
  fprintf(stderr,"AUDIT %u %u %u %u\\n",rows,channels,io_park.head!=NULL,sockets);
}
'''
(ROOT/'build/udp-read-race-audit.c').write_text((ROOT/'build/udp-read-race.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-read-race-audit.c','-lpthread','-lm','-o','build/udp-read-race'],cwd=ROOT,check=True)
def line(stream):
    data=b'';until=time.monotonic()+10
    while not data.endswith(b'\n'):
        assert select.select([stream],[],[],max(0,until-time.monotonic()))[0],'fixture timed out'
        byte=stream.read(1);assert byte,'early exit';data+=byte
    return data.decode().strip()
rows=[]
delays=[0,0.010,0.019,0.020,0.021,0.040]*10
for backend,cmd in [('native 1',['build/udp-read-race','--threads','1']),('native 4',['build/udp-read-race','--threads','4']),('Bun',[str(bun),'build/udp-read-race.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        with socket.socket(af,socket.SOCK_DGRAM) as peer:
            peer.bind((host,0))
            p=subprocess.Popen([*cmd,str(family),str(len(delays))],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
            try:
                local=line(p.stdout).split(',');assert local[:5]==[str(family),'0','0','0','0'],local
                outcomes=[]
                for index,delay in enumerate(delays):
                    assert line(p.stdout)=='armed'
                    time.sleep(delay)
                    peer.sendto(bytes([index]),(host,int(local[5])))
                    outcome=line(p.stdout);assert outcome in ['packet','cancelled'],outcome
                    outcomes.append(outcome)
                assert line(p.stdout)=='done'
                out,err=p.communicate(timeout=8)
                assert p.returncode==0 and not out and err==(b'' if backend=='Bun' else b'AUDIT 0 0 0 0\n'),(backend,family,p.returncode,out,err)
                assert set(outcomes)=={'packet','cancelled'},(backend,family,outcomes)
                rows.append(dict(backend=backend,family=family,delays_seconds=delays,outcomes=outcomes,native_audit=err.decode().strip()))
            finally:
                if p.poll() is None:p.kill();p.wait()
    print(f'{backend}: {2*len(delays)} read/packet races PASS',flush=True)
paths=['tests/udp-read-race.bend','tests/udp_read_race_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={s:json.loads((ROOT/f'build/udp-read-race-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-read-race-result.json').write_text(json.dumps(r,indent=2)+'\n')
