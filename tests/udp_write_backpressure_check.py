"""Test-only EAGAIN injection exercises owned-send parking, cancellation and resume.

Run udp_write_check.py first. No candidate or installed effects are modified.
This validates the scheduling branch, not occurrence of real OS backpressure.
"""
import hashlib,json,os,re,select,socket,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun'
validated=json.loads((ROOT/'build/udp-write-result.json').read_text())
for path,digest in validated['sha256'].items():
    if path.endswith(('.bend','.c','.js')):assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
source=(ROOT/'build/udp-write-audit.c').read_text()
needle='static Term udp_send_packet('
assert source.count(needle)==1
helper='''
static unsigned udp_test_blocks;
static ssize_t udp_test_sendto(int fd,const void* data,size_t size,int flags,const struct sockaddr* to,socklen_t length) {
  if(size==256 && ((const unsigned char*)data)[0]==0) {
    const char* raw=getenv("UDP_TEST_RELEASE_AFTER");
    unsigned limit=raw ? (unsigned)strtoul(raw,NULL,10) : 0;
    if(!limit || udp_test_blocks<limit) { udp_test_blocks++; errno=EAGAIN; return -1; }
  }
  return sendto(fd,data,size,flags,to,length);
}
static void __attribute__((destructor)) udp_test_audit(void) { fprintf(stderr,"BLOCKED %u\\n",udp_test_blocks); }
'''
source=source.replace(needle,helper+'\n'+needle).replace('ssize_t n = sendto(fd,','ssize_t n = udp_test_sendto(fd,')
(ROOT/'build/udp-write-blocked.c').write_text(source)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/udp-write-blocked.c','-lpthread','-lm','-o','build/udp-write-blocked'],cwd=ROOT,check=True)
source=(ROOT/'build/udp-write.js').read_text()
a=source.index('function udp_send_start(');b=source.index('\nfunction udp_send_bytes(',a)
part=source[a:b]
needle='const n = Number(sys.sendto(socket, sys.ptr(bytes), length, 0, sys.ptr(at), at.length));'
assert part.count(needle)==1
part=part.replace(needle,'''const limit=Number(process.env.UDP_TEST_RELEASE_AFTER || 0);
    const blocks=globalThis.UDP_TEST_BLOCKS || 0;
    const forced=length===256 && bytes[0]===0 && (!limit || blocks<limit);
    if(forced) globalThis.UDP_TEST_BLOCKS=blocks+1;
    const n = forced ? -1 : Number(sys.sendto(socket, sys.ptr(bytes), length, 0, sys.ptr(at), at.length));''').replace('const code = sys.errno();','const code = forced ? (sys.mac ? 35 : 11) : sys.errno();')
source=source[:a]+part+source[b:]
source='process.on("exit",()=>console.error("BLOCKED "+(globalThis.UDP_TEST_BLOCKS || 0)));\n'+source
(ROOT/'build/udp-write-blocked.js').write_text(source)
rows=[]
for backend,cmd in [('native 1',['build/udp-write-blocked','--threads','1']),('native 4',['build/udp-write-blocked','--threads','4']),('Bun',[str(bun),'build/udp-write-blocked.js'])]:
    for family,af,host in [(4,socket.AF_INET,'127.0.0.1'),(6,socket.AF_INET6,'::1')]:
        for limit,mode in [(0,'park'),(3,'ok')]:
            with socket.socket(af,socket.SOCK_DGRAM) as peer:
                peer.bind((host,0));peer.settimeout(5)
                run=subprocess.run([*cmd,str(family),str(peer.getsockname()[1]),'256',mode],cwd=ROOT,env={**os.environ,'UDP_TEST_RELEASE_AFTER':str(limit)},capture_output=True,text=True,timeout=8)
                assert run.returncode==0 and run.stdout.splitlines()==(['cancelled','ok'] if not limit else ['ok','ok']),(backend,family,limit,run)
                blocked=re.findall(r'^BLOCKED (\d+)$',run.stderr,re.M);assert len(blocked)==1 and int(blocked[0])>0,(backend,run)
                if limit:assert int(blocked[0])==limit
                extra=[line for line in run.stderr.splitlines() if not line.startswith('BLOCKED ')]
                assert extra==([] if backend=='Bun' else ['AUDIT 0 0 0 0']),run
                if limit:assert peer.recv(65536)==bytes(range(256))
                assert peer.recv(65536)==b'\x11\0\xff'
                assert not select.select([peer],[],[],0)[0]
                rows.append(dict(backend=backend,family=family,resume_after=limit,parked_attempts=int(blocked[0]),outcome=run.stdout.splitlines(),audit=extra))
    print(f'{backend}: 4 injected-backpressure cases PASS',flush=True)
paths=['tests/udp_write_backpressure_check.py','tests/udp-write.bend','build/udp-write-blocked.c','build/udp-write-blocked.js']
r=dict(scope=__doc__,runs=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},validated_candidate=validated['sha256'])
(ROOT/'build/udp-write-backpressure-result.json').write_text(json.dumps(r,indent=2)+'\n')
