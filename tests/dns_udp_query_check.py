"""Live numeric UDP DNS attempts under nested deadlines; reply filtering, encoding and cleanup."""
import hashlib,json,re,select,socket,struct,subprocess,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';candidate=ROOT/'build/bend-udp-peer-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-udp-query-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/dns-udp-query.bend','-o',f'build/dns-udp-query.{suffix}'],cwd=ROOT,check=True)
source=(ROOT/'build/dns-udp-query.c').read_text()+'''
static void __attribute__((destructor)) query_audit(void) {
  unsigned reads=0,writes=0,timers=0,channels=0,sockets=0;
  for(u32 i=0;i<udp_read_len;i++)reads+=udp_read_rows[i].live;
  for(u32 i=0;i<udp_write_len;i++)writes+=udp_write_rows[i].live;
  for(u32 i=0;i<timer_len;i++)timers+=timer_rows[i].live;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  fprintf(stderr,"AUDIT %u %u %u %u %u %u\\n",reads,writes,timers,channels,sockets,io_park.head!=NULL);
}
'''
(ROOT/'build/dns-udp-query-audit.c').write_text(source)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-udp-query-audit.c','-lpthread','-lm','-o','build/dns-udp-query'],cwd=ROOT,check=True)
(ROOT/'build/dns-udp-query-audit.js').write_text('process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+(ROOT/'build/dns-udp-query.js').read_text())
def packet(flags=0x8180,ident=42,question=b'\0\0\1\0\1',qd=1,answer=b'',an=0):
    return struct.pack('!6H',ident,flags,qd,an,0,0)+question+answer
plain_query=struct.pack('!6H',42,256,1,0,0,0)+b'\0\0\1\0\1'
modes=['answer','edns','truncated','noise-then-answer','noise','silent','large','rcode','total','later','pre','pre-default','invalid','port','refused']
rows=[]
for backend,command in [('native 1',['build/dns-udp-query','--threads','1']),('native 4',['build/dns-udp-query','--threads','4']),('Bun',[str(bun),'build/dns-udp-query-audit.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for mode in modes:
            with socket.socket(af,socket.SOCK_DGRAM) as peer,socket.socket(af,socket.SOCK_DGRAM) as outsider:
                peer.bind((host,0));peer.settimeout(3);outsider.bind((host,0))
                port=peer.getsockname()[1]
                if mode=='refused':peer.close()
                p=subprocess.Popen([*command,str(family),str(port),mode],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                stop=threading.Event();noise_thread=None;start=time.monotonic();wire=None
                try:
                    if mode not in ['pre','pre-default','invalid','port','refused']:
                        wire,client=peer.recvfrom(65536)
                        expected_query=plain_query if mode!='edns' else plain_query[:10]+b'\0\1'+plain_query[12:]+b'\0\0\x29\x04\xd0'+b'\0'*6
                        assert wire==expected_query,(mode,wire,expected_query)
                        response=packet()
                        if mode=='edns':response=packet()
                        elif mode=='truncated':response=packet(0x8380)
                        elif mode=='rcode':response=packet(0x8183)
                        elif mode=='large':response=packet(answer=b'\xc0\x0c'+struct.pack('!HHIH',65000,1,0,4096)+bytes([0,255])*2048,an=1)
                        elif mode=='noise-then-answer':
                            for bad in [b'',b'bad',packet(ident=43),packet(flags=0x0180),packet(flags=0x8980),packet(question=b'',qd=0),packet(question=b'\0\0\x1c\0\1'),packet(flags=0x8380,question=b'\0\0\x1c\0\1'),packet(question=b'\xc0\x0c\0\1\0\1')]:peer.sendto(bad,client)
                            outsider.sendto(packet(0x8185),client)
                        if mode=='noise':
                            def noise():
                                while not stop.is_set():
                                    peer.sendto(packet(ident=43),client)
                                    stop.wait(0.002)
                            noise_thread=threading.Thread(target=noise);noise_thread.start()
                        elif mode not in ['silent','total','later']:peer.sendto(response,client)
                    out,err=p.communicate(timeout=6);elapsed=time.monotonic()-start
                    stop.set()
                    if noise_thread:noise_thread.join()
                    if mode in ['silent','noise']:expected=['abort:attempt','attempt']
                    elif mode=='total':expected=['abort:total','total']
                    elif mode in ['later','pre']:expected=['abort:caller:stop','caller:stop']
                    elif mode=='pre-default':expected=['abort:caller:default','caller:default']
                    elif mode=='invalid':expected=['invalid','active']
                    elif mode=='port':expected=['association:22','active']
                    elif mode=='refused':expected=['socket:111','active']
                    elif mode=='truncated':expected=['truncated','active']
                    else:expected=[f'answer:{struct.unpack("!H",response[2:4])[0]}:{len(response)}:{response[-1]}','active']
                    assert p.returncode==0 and out.splitlines()==expected and err==('AUDIT 0 0\n' if backend=='Bun' else 'AUDIT 0 0 0 0 0 0\n'),(backend,family,mode,out,err)
                    if mode!='refused':assert not select.select([peer],[],[],0)[0],'unexpected extra query or retransmission'
                    if mode in ['silent','noise']:assert elapsed>=0.9
                    rows.append(dict(backend=backend,family=family,mode=mode,seconds=elapsed,request_hex=wire.hex() if wire else None,result=out.splitlines(),audit=err.strip()))
                finally:
                    stop.set()
                    if noise_thread:noise_thread.join()
                    if p.poll() is None:p.kill();p.wait()
    print(f'{backend}: {2*len(modes)} live UDP DNS attempts PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-udp-query.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_udp_query_check.py']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/dns-udp-query-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/dns-udp-query-result.json').write_text(json.dumps(r,indent=2)+'\n')
