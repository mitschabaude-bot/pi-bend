"""Abortable UDP sends preserve reasons, delivery and socket ownership and clean up watchers/timers."""
import hashlib,json,os,re,select,socket,subprocess,sys
from pathlib import Path
from udp_backpressure import inject
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
candidate=(ROOT/sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'build/bend-udp-write-candidate'
stem='abortable-datagram-send'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{stem}-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),f'tests/{stem}.bend','-o',f'build/{stem}.{suffix}'],cwd=ROOT,check=True)
audit='''
static void __attribute__((destructor)) send_audit(void) {
  unsigned rows=0,channels=0,sockets=0,timers=0;
  for(u32 i=0;i<udp_write_len;i++) rows+=udp_write_rows[i].live;
  for(u32 i=0;i<timer_len;i++) timers+=timer_rows[i].live;
  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  fprintf(stderr,"AUDIT %u %u %u %u %u\\n",rows,channels,io_park.head!=NULL,sockets,timers);
}
'''
(ROOT/f'build/{stem}-audit.c').write_text((ROOT/f'build/{stem}.c').read_text()+audit)
inject(ROOT/f'build/{stem}-audit.c',ROOT/f'build/{stem}-blocked.c',ROOT/f'build/{stem}.js',ROOT/f'build/{stem}-blocked.js')
for version,source in [('',f'{stem}-audit.c'),('-blocked',f'{stem}-blocked.c')]:
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{source}','-lpthread','-lm','-o',f'build/{stem}{version}'],cwd=ROOT,check=True)
rows=[]
for backend in ['native 1','native 4','Bun']:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        cases=[(False,'ok',0,'ok','none'),(False,'ok',256,'ok','none'),(False,'pre',256,'abort:parent:stop','parent:stop'),(False,'byte',256,'error:22','none'),(False,'port',0,'error:22','none'),(False,'ok',65536,'error:90','none')]
        cases += [(True,mode,256,outcome,scope) for mode,outcome,scope in [('custom','abort:parent:stop','parent:stop'),('default','abort:default','default'),('deadline','abort:expiry','expiry'),('pre','abort:parent:stop','parent:stop'),('ok','ok','none')]]
        for blocked,mode,size,outcome,scope in cases:
            for count in [1,10]:
                suffix='-blocked' if blocked else ''
                cmd=[str(bun),f'build/{stem}{suffix}.js'] if backend=='Bun' else [f'build/{stem}{suffix}','--threads',backend[-1]]
                with socket.socket(af,socket.SOCK_DGRAM) as peer:
                    peer.bind((host,0));peer.settimeout(3)
                    run=subprocess.run([*cmd,str(family),str(peer.getsockname()[1]),mode,str(size),str(count)],cwd=ROOT,env={**os.environ,'UDP_TEST_RELEASE_AFTER':'3' if mode=='ok' else '0'},capture_output=True,text=True,timeout=10)
                    assert run.returncode==0 and run.stdout.splitlines()==[outcome,'scope:'+scope]*count+['ok'],(backend,family,blocked,mode,size,count,run)
                    blocks=re.findall(r'^BLOCKED (\d+)$',run.stderr,re.M)
                    if blocked:
                        assert len(blocks)==1
                        if mode in ['ok','pre']:assert int(blocks[0])==(0 if mode=='pre' else 3)
                        else:assert int(blocks[0])>0
                    else:assert not blocks
                    extra=[x for x in run.stderr.splitlines() if not x.startswith('BLOCKED ')]
                    assert extra==([] if backend=='Bun' else ['AUDIT 0 0 0 0 0']),run
                    sender=None
                    if outcome=='ok':
                        for _ in range(count):
                            packet,source=peer.recvfrom(65536)
                            assert packet==bytes(i%256 for i in range(size))
                            assert sender is None or sender==source
                            sender=source
                    marker,source=peer.recvfrom(65536)
                    assert marker==b'\x11\0\xff' and (sender is None or sender==source)
                    assert not select.select([peer],[],[],0)[0],'unexpected datagram'
                    rows.append(dict(backend=backend,family=family,injected_backpressure=blocked,mode=mode,size=size,count=count,outcome=outcome,scope=scope,blocked_attempts=blocks,audit=extra))
    print(f'{backend}: 44 abortable send scenarios PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^ ]+)',path.read_text(),re.M):
        imports(path.parent/relative)
imports(ROOT/f'tests/{stem}.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/abortable_datagram_send_check.py','tests/udp_backpressure.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
result=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/{stem}-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/f'build/{stem}-result.json').write_text(json.dumps(result,indent=2)+'\n')
