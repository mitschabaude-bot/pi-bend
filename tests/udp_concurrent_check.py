"""Concurrent UDP owner growth, parked-read cancellation, buffered-write release and generation reuse.

Read parking is observed in generated test-only audit copies. Writes remain
unstarted; parked write cancellation is covered by the separate injection suite.
"""
import hashlib,json,os,re,subprocess
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun'
candidate=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/udp-concurrent-{suffix}-build.json','--',str(bun),str(candidate/'main.ts'),'tests/udp-concurrent.bend','-o',f'build/udp-concurrent.{suffix}'],cwd=ROOT,check=True)
source=(ROOT/'build/udp-concurrent.c').read_text()
needle='static Term udp_read_more(Env e, IoWork* w) {'
assert source.count(needle)==1
source=source.replace(needle,'static unsigned udp_test_peak;\n'+needle)
needle='return io_wait_on(w, row->fd, POLLIN, udp_read_more);'
assert source.count(needle)==1
source=source.replace(needle,'''unsigned parked=0;
    for(u32 i=0;i<udp_read_len;i++) parked+=udp_read_rows[i].waiter!=NULL;
    if(parked>udp_test_peak) udp_test_peak=parked;
    '''+needle)
source+='''
static void __attribute__((destructor)) udp_concurrent_audit(void) {
  unsigned reads=0,writes=0,buffers=0,channels=0,sockets=0;
  for(u32 i=0;i<udp_read_len;i++) reads+=udp_read_rows[i].live;
  for(u32 i=0;i<udp_write_len;i++) {
    writes+=udp_write_rows[i].live;
    buffers+=udp_write_rows[i].payload.data!=NULL || udp_write_rows[i].payload.text!=NULL;
  }
  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  fprintf(stderr,"AUDIT %u %u %u %u %u %u %u %u %u\\n",reads,writes,buffers,channels,sockets,io_park.head!=NULL,udp_read_len,udp_write_len,udp_test_peak);
}
'''
(ROOT/'build/udp-concurrent-audit.c').write_text(source)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-concurrent-audit.c','-lpthread','-lm','-o','build/udp-concurrent'],cwd=ROOT,check=True)
source=(ROOT/'build/udp-concurrent.js').read_text()
a=source.index('function udpread_wait(');b=source.index('function udpread_cancel(',a)
part=source[a:b];needle='globalThis.BEND_IO.waits.push(wait);';assert part.count(needle)==1
part=part.replace(needle,needle+'\n    globalThis.UDP_TEST_PEAK=Math.max(globalThis.UDP_TEST_PEAK||0,globalThis.BEND_IO.waits.filter(w=>w.fd!==undefined&&!w.out).length);')
source=source[:a]+part+source[b:]
source='process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length} ${globalThis.UDP_TEST_PEAK}`));\n'+source
(ROOT/'build/udp-concurrent-audit.js').write_text(source)
rows=[]
for backend,cmd in [('native 1',['build/udp-concurrent','--threads','1']),('native 4',['build/udp-concurrent','--threads','4']),('Bun',[str(bun),'build/udp-concurrent-audit.js'])]:
    for family in [4,6]:
        for width,waves,size in [(1,20,0),(32,20,256),(128,10,65535),(128,100,256)]:
            stats=ROOT/'build/udp-concurrent-process.txt'
            run=subprocess.run(['/usr/bin/time','-f','%e %M','-o',str(stats),*cmd,str(family),str(width),str(waves),str(size)],cwd=ROOT,capture_output=True,text=True,timeout=60)
            audit=f'AUDIT 0 0 {width}\n' if backend=='Bun' else f'AUDIT 0 0 0 0 0 0 {width} {width} {width}\n'
            assert run.returncode==0 and run.stdout=='ok\n' and run.stderr==audit,(backend,family,width,waves,size,run)
            seconds,rss=map(float,stats.read_text().split())
            rows.append(dict(backend=backend,family=family,width=width,waves=waves,payload_size=size,seconds=seconds,peak_rss_kib=rss,audit=run.stderr.strip()))
    print(f'{backend}: 8 concurrent UDP scenarios PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/udp-concurrent.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/udp_concurrent_check.py','build/udp-concurrent-audit.c','build/udp-concurrent-audit.js']+[str(p.relative_to(ROOT)) for p in (ROOT/'patches/experimental/udp-bytes').glob('*')]
result=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/udp-concurrent-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/udp-concurrent-result.json').write_text(json.dumps(result,indent=2)+'\n')
