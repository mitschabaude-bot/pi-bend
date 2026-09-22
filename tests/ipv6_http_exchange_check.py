"""Typed URL -> numeric IPv6 connect -> full cleartext HTTP exchange.

All traffic is local. Compares fixed/chunked uploads and three response framing
modes with Node Fetch. This is not DNS, TLS or cancellable-connect coverage.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,help='compiler directory providing TCP.connect_ipv6; the installed toolchain does not yet')
parser.add_argument('--no-native-build',action='store_true')
args=parser.parse_args();candidate=args.candidate.resolve()
launcher=ROOT/'build/ipv6-http-compiler'
launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(Path.home()/'.bun/bin/bun'))+' '+shlex.quote(str(candidate/'main.ts'))+' "$@"\n');launcher.chmod(0o755)
if not args.no_native_build:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','24','--stats','build/ipv6-http-build.json','--','sh','scripts/build-pure.sh','tests/ipv6-http-exchange.bend','build/ipv6-http-exchange'],cwd=ROOT,env=dict(os.environ,BEND=str(launcher)),check=True)
subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats','build/ipv6-http-js-build.json','--',str(launcher),'tests/ipv6-http-exchange.bend','-o','build/ipv6-http-exchange.js'],cwd=ROOT,check=True)
body='{"text":"hé🙂"}'.encode()

def chunks(wire):
    position=0;output=bytearray()
    while True:
        end=wire.find(b'\r\n',position)
        if end<0:return None
        size=int(wire[position:end],16);position=end+2
        if len(wire)<position+size+2:return None
        assert wire[position+size:position+size+2]==b'\r\n'
        if size==0:
            assert len(wire)==position+2
            return bytes(output)
        output.extend(wire[position:position+size]);position+=size+2

def check(label,command):
    captured=[]
    with socket.socket(socket.AF_INET6,socket.SOCK_STREAM) as listener,ThreadPoolExecutor(max_workers=1) as pool:
        listener.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
        listener.bind(('::1',0));listener.listen(16);listener.settimeout(15)
        port=listener.getsockname()[1]
        def serve():
            for index in range(24):
                with listener.accept()[0] as peer:
                    peer.settimeout(10);buffer=b''
                    while b'\r\n\r\n' not in buffer:
                        chunk=peer.recv(1024);assert chunk and len(buffer)<16384;buffer+=chunk
                    head,received=buffer.split(b'\r\n\r\n',1)
                    first,*lines=head.split(b'\r\n');fields={}
                    for line in lines:
                        name,value=line.split(b':',1);fields.setdefault(name.lower(),[]).append(value.lstrip(b' \t'))
                    target=b'/v1/responses?'+(b'' if index%4>=2 else b'x=%C3%A9')
                    assert first==(b'DELETE' if index%2 else b'POST')+b' '+target+b' HTTP/1.1',first
                    expected={b'host':[f'[::1]:{port}'.encode()],b'content-type':[b'application/json'],b'x-byte':[b'\xff']}
                    if index%2:
                        expected[b'transfer-encoding']=[b'chunked'];assert b'content-length' not in fields
                        decoded=chunks(received)
                        while decoded is None:
                            chunk=peer.recv(1024);assert chunk;received+=chunk;decoded=chunks(received)
                        received=decoded
                    else:
                        expected[b'content-length']=[str(len(body)).encode()];assert b'transfer-encoding' not in fields
                        while len(received)<len(body):
                            chunk=peer.recv(1024);assert chunk;received+=chunk
                    assert {name:fields.get(name) for name in expected}==expected,fields
                    assert received==body,received
                    captured.append({'request_line':first.decode(),'headers':{k.decode():[v.decode('latin1') for v in values] for k,values in expected.items() if k!=b'host'},'host':'[::1]:<port>','body_hex':received.hex(),'response_framing':index%3})
                    if index%3==0:
                        peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK')
                    elif index%3==1:
                        peer.sendall(b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: x-finish\r\nConnection: close\r\n\r\n1\r\nO\r\n1\r\nK\r\n0\r\nx-finish: yes\r\n\r\n')
                    else:
                        peer.sendall(b'HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nOK');peer.shutdown(socket.SHUT_WR)
                    assert peer.recv(1)==b'',(label,index,'client did not close connection')
        future=pool.submit(serve)
        run=subprocess.run([*command,'p'+str(port)],cwd=ROOT,capture_output=True,text=True,timeout=45)
        future.result(timeout=20)
        assert run.returncode==0,(label,run.stdout,run.stderr)
        assert run.stdout=='PASS IPv6 HTTP exchange\n' and not run.stderr,(label,run)
    print(label+': 24 full IPv6 HTTP exchanges PASS',flush=True)
    return captured

oracle=r'''
const port=process.argv[1].slice(1);
for(let i=0;i<24;i++){
 const query=i%4>=2?'':'x=%C3%A9';
 const r=await fetch('http://[::1]:'+port+'/v1/responses?'+query+'#ignored',{
  method:i%2?'delete':'post',headers:{host:'override.invalid','content-type':'application/json','x-byte':'\xff',...(i%2?{'content-length':'0'}:{})},
  body:'{"text":"hé🙂"}',signal:AbortSignal.timeout(5000)});
 if(r.status!==200||await r.text()!=='OK')throw Error('wrong response');
}
console.log('PASS IPv6 HTTP exchange');
'''
reference=check('Node Fetch',['node','--input-type=module','-e',oracle])
for label,command in [('native 1',['build/ipv6-http-exchange','--threads','1']),('native 4',['build/ipv6-http-exchange','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/ipv6-http-exchange.js'])]:
    assert check(label,command)==reference,label
record={'scope':__doc__,'node_versions':json.loads(subprocess.check_output(['node','-p','JSON.stringify(process.versions)'],text=True)),'cases_per_backend':24,'backends':['Node Fetch','native 1','native 4','Bun'],'observed':reference,'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'tests/ipv6-http-exchange.bend',ROOT/'build/ipv6-http-exchange.c',ROOT/'build/ipv6-http-exchange',ROOT/'build/ipv6-http-exchange.js']},'compiler_sha256':hashlib.sha256((candidate/'comp.ts').read_bytes()).hexdigest()}
(ROOT/'build/ipv6-http-result.json').write_text(json.dumps(record,indent=2)+'\n')
