"""Numeric IPv6 primitive contracts against local IPv6/IPv4 loopback peers.

64 serial lifecycles per case; Linux descriptor samples are bounded observations,
not proof of leak freedom. No DNS, TLS or cancellation coverage is claimed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate', type=Path)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
candidate=args.candidate.resolve()
bun=Path.home()/'.bun/bin/bun'
if not args.no_build:
    subprocess.run([str(bun),str(candidate/'main.ts'),'tests/ipv6-connect.bend','-o','build/ipv6-connect.c'],cwd=ROOT,check=True)
    subprocess.run(['clang','-fbracket-depth=2048','-std=c11','-O1','build/ipv6-connect.c','-lpthread','-lm','-o','build/ipv6-connect'],cwd=ROOT,check=True)
subprocess.run([str(bun),str(candidate/'main.ts'),'tests/ipv6-connect.bend','-o','build/ipv6-connect.js'],cwd=ROOT,check=True)
report={'scope':__doc__,'cases':[],'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [candidate/'base.bend',candidate/'comp.ts',candidate/'effs/tcp_connect_ipv6.c',candidate/'effs/tcp_connect_ipv6.js',ROOT/'tests/ipv6-connect.bend',ROOT/'build/ipv6-connect',ROOT/'build/ipv6-connect.js']}}
for label,command in [('native 1',['build/ipv6-connect','--threads','1']),('native 4',['build/ipv6-connect','--threads','4']),('Bun',[str(bun),'build/ipv6-connect.js'])]:
    for family,bind,address in [(socket.AF_INET6,'::1','::1'),(socket.AF_INET,'127.0.0.1','::ffff:127.0.0.1')]:
        with socket.socket(family,socket.SOCK_STREAM) as listener:
            if family==socket.AF_INET6:listener.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
            listener.bind((bind,0));listener.listen(16);listener.settimeout(15)
            port=listener.getsockname()[1]
            ready=threading.Event();pid=[]
            def serve():
                ready.wait(10);counts=[]
                for _ in range(64):
                    with listener.accept()[0] as peer:
                        peer.settimeout(10);data=b''
                        while len(data)<4:
                            chunk=peer.recv(4-len(data));assert chunk,'early EOF';data+=chunk
                        assert data==b'ping',data
                        counts.append(len(list(Path(f'/proc/{pid[0]}/fd').iterdir())))
                        peer.sendall(b'x')
                return counts
            with ThreadPoolExecutor(max_workers=1) as pool:
                task=pool.submit(serve)
                process=subprocess.Popen([*command,address,str(port),'0'],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                pid.append(process.pid);ready.set()
                try:output,errors=process.communicate(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill();process.communicate();raise
                counts=task.result(timeout=20)
            assert process.returncode==0,(label,address,errors)
            assert output.splitlines()==['ok:x']*64,(label,address,output)
            assert max(counts)-min(counts)<=4,(label,address,'descriptor growth',counts)
            report['cases'].append({'backend':label,'address':address,'successes':64,'live_fd_samples':counts})
    # Binding without listening reserves a closed port throughout the run.
    with socket.socket(socket.AF_INET6,socket.SOCK_STREAM) as closed:
        closed.bind(('::1',0));port=closed.getsockname()[1]
        for test_port,expected in [(port,errno.ECONNREFUSED),(65536,errno.EINVAL),(4294967295,errno.EINVAL)]:
            run=subprocess.run([*command,'::1',str(test_port),'0'],cwd=ROOT,capture_output=True,text=True,timeout=30)
            assert run.returncode==0,(label,run.stderr)
            assert run.stdout.splitlines()==[f'error:{expected}']*64,(label,test_port,run.stdout)
            report['cases'].append({'backend':label,'port':test_port,'failures':64,'errno':expected})
    print(f'{label}: IPv6/mapped IPv4 exchange, refusal and port bounds PASS',flush=True)
(ROOT/'build/ipv6-connect-result.json').write_text(json.dumps(report,indent=2)+'\n')
