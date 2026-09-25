"""Numeric UDP peer association: actual route metadata, peer filtering and reassociation."""
import hashlib,json,re,select,socket,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';candidate=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-peer-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-peer.bend','-o',f'build/udp-peer.{suffix}'],cwd=ROOT,check=True)
source=(ROOT/'build/udp-peer.c').read_text()+'''
static void __attribute__((destructor)) peer_audit(void) {
  unsigned sockets=0;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  fprintf(stderr,"AUDIT %u %u\\n",sockets,io_park.head!=NULL);
}
'''
(ROOT/'build/udp-peer-audit.c').write_text(source)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-peer-audit.c','-lpthread','-lm','-o','build/udp-peer'],cwd=ROOT,check=True)
rows=[]
for backend,cmd in [('native 1',['build/udp-peer','--threads','1']),('native 4',['build/udp-peer','--threads','4']),('Bun',[str(bun),'build/udp-peer.js'])]:
    for family,af,host,address in [(4,socket.AF_INET,'127.0.0.1',[4,2130706433,0,0,0]),(6,socket.AF_INET6,'::1',[6,0,0,0,1])]:
        for mode in ['ok','family','zero','large']+(['word','scope'] if family==4 else []):
            with socket.socket(af,socket.SOCK_DGRAM) as first,socket.socket(af,socket.SOCK_DGRAM) as second,socket.socket(af,socket.SOCK_DGRAM) as outsider:
                for peer in [first,second,outsider]:peer.bind((host,0));peer.settimeout(3)
                ports=[first.getsockname()[1],second.getsockname()[1]]
                p=subprocess.Popen([*cmd,str(family),*map(str,ports),mode],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                senders=[]
                try:
                    for i,peer in enumerate([first,second]):
                        data,sender=peer.recvfrom(64);assert data==b'\0\xff'
                        senders.append(sender)
                        outsider.sendto(b'\x63',sender)
                        if i:first.sendto(b'\x62',sender)
                        peer.sendto(b'\x11\0\xff',sender)
                    out,err=p.communicate(timeout=5)
                    assert p.returncode==0 and err==('' if backend=='Bun' else 'AUDIT 0 0\n'),(backend,mode,p.returncode,err)
                    assert senders[0]==senders[1],senders
                    local=','.join(map(str,address+[senders[0][1],0]))
                    expected=[] if mode=='ok' else ['error:22']
                    for port in ports:
                        remote=','.join(map(str,address+[port,0]))
                        packet=':'.join(map(str,address+[port,0]))+':0:17,0,255,'
                        expected+=['ok',local,remote,'ok',packet]
                    assert out.splitlines()==expected,(backend,family,mode,out,expected)
                    assert not select.select([first,second,outsider],[],[],0)[0]
                    rows.append(dict(backend=backend,family=family,mode=mode,audit=err.strip(),source_port_preserved=True))
                finally:
                    if p.poll() is None:p.kill();p.wait()
    print(f'{backend}: 10 UDP peer scenarios PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/udp-peer.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/udp_peer_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/udp-peer-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-peer-result.json').write_text(json.dumps(r,indent=2)+'\n')
