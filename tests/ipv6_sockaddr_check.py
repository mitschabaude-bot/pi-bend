"""Audit all IPv6 sockaddr fields at a disposable connect syscall boundary.

The temporary effects print the constructed sockaddr and synthesize EINVAL.
No external address is contacted. Real loopback behavior is a separate check.
"""
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shutil
import socket
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve();bun=Path.home()/'.bun/bin/bun'
helper=r'''
static int ipv6_probe_connect(int fd, const struct sockaddr* address, socklen_t length) {
  (void)fd;
  const struct sockaddr_in6* at = (const struct sockaddr_in6*)address;
  fprintf(stderr, "%u:%u:%u:%u:%u:", (unsigned)length, (unsigned)at->sin6_family,
    (unsigned)ntohs(at->sin6_port), (unsigned)at->sin6_scope_id, (unsigned)at->sin6_flowinfo);
  for (unsigned i = 0; i < 16; ++i) fprintf(stderr, "%02x", at->sin6_addr.s6_addr[i]);
  fprintf(stderr, "\n");
  errno = EINVAL;
  return -1;
}
'''
inputs=[([0,0,0,1],0,0),([0x01020304,0x11223344,0x89abcdef,0xfedcba98],1,1),([0xffffffff]*4,65535,0xffffffff),([0x80000000,1,0xffff0000,0x0000ffff],443,7)]
rows=[]
with tempfile.TemporaryDirectory(prefix='ipv6-sockaddr-',dir=ROOT/'build') as directory:
    folder=Path(directory);compiler=folder/'bend2';shutil.copytree(candidate,compiler)
    effect=compiler/'effs/tcp_connect_ipv6.c';original=effect.read_text()
    needle='connect(fd, (struct sockaddr*)&at, sizeof(at))';assert original.count(needle)==1
    effect.write_text(helper+original.replace(needle,'ipv6_probe_connect(fd, (struct sockaddr*)&at, sizeof(at))'))
    effect=compiler/'effs/tcp_connect_ipv6.js';original=effect.read_text()
    needle='const code = sys.connect(fd, sys.ptr(address), address.length) >= 0 ? 0 : sys.errno();';assert original.count(needle)==1
    effect.write_text(original.replace(needle,"console.error([address.length, family, view.getUint16(2, false), view.getUint32(24, little), view.getUint32(4, little), [...address.subarray(8, 24)].map(x=>x.toString(16).padStart(2, '0')).join('')].join(':')); const code = 22;"))
    for suffix in ['c','js']:
        subprocess.run([str(bun),str(compiler/'main.ts'),'tests/ipv6-connect-words.bend','-o',str(folder/f'probe.{suffix}')],cwd=ROOT,check=True,capture_output=True,timeout=60)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-fbracket-depth=2048','-std=c11','-O1',str(folder/'probe.c'),'-lpthread','-lm','-o',str(folder/'probe')],check=True,timeout=60)
    for label,command in [('native 1',[str(folder/'probe'),'--threads','1']),('native 4',[str(folder/'probe'),'--threads','4']),('Bun',[str(bun),str(folder/'probe.js')])]:
        for words,port,scope in inputs:
            run=subprocess.run([*command,*map(str,[*words,port,scope])],capture_output=True,text=True,timeout=10)
            expected=f'28:{socket.AF_INET6}:{port}:{scope}:0:'+b''.join(w.to_bytes(4,'big') for w in words).hex()
            assert run.returncode==0 and run.stdout=='22\n' and run.stderr.strip()==expected,(label,run,expected)
            rows.append({'backend':label,'words':words,'port':port,'scope':scope,'observed':run.stderr.strip()})
        print(label,'all sockaddr fields PASS',flush=True)
report={'scope':__doc__,'platform':sys.platform,'cases':rows,'production_sha256':{name:hashlib.sha256((candidate/'effs'/name).read_bytes()).hexdigest() for name in ['tcp_connect_ipv6.c','tcp_connect_ipv6.js']}}
(ROOT/'build/ipv6-sockaddr-result.json').write_text(json.dumps(report,indent=2)+'\n')
