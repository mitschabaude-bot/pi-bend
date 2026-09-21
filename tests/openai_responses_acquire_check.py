"""Native Responses hook/envelope/attempt integration against a loopback peer."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import argparse
import json
import re
import socket
import subprocess
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',type=Path,default=ROOT/'build/openai-responses-acquire')
mode=parser.add_mutually_exclusive_group()
mode.add_argument('--js-only',action='store_true')
mode.add_argument('--js-audit',action='store_true')
args=parser.parse_args()
PREFIX=args.prefix.resolve()
BUN=str(Path.home()/'.bun/bin/bun')
PAYLOAD='payload:"original":target'
# The fixture renders the exact binary64 status bits.
STATUS=struct.unpack('!II',struct.pack('!d',200.0))
RESPONSE=f'response:{STATUS[0]}:{STATUS[1]}:target'
# Hook replacement must survive retry without rerunning the hook.
CASES=[
 ('no-hooks',0,b'"original"',1,['request','accepted','body:ok','count:1']),
 ('unchanged',1,b'"original"',1,[PAYLOAD,'request',RESPONSE,'accepted','body:ok','count:1']),
 ('replacement-retry',2,b'"replacement"',2,[PAYLOAD,'request','sleep','request',RESPONSE,'accepted','body:ok','count:2']),
 ('zero',3,b'0',1,[PAYLOAD,'request',RESPONSE,'accepted','body:ok','count:1']),
 ('payload-failure',4,None,0,[PAYLOAD,'failed:payload:payload','count:0']),
 ('response-failure',5,b'"original"',1,[PAYLOAD,'request',RESPONSE,'release','failed:response:response:ok','count:1']),
 ('response-and-cleanup-failure',6,b'"original"',1,[PAYLOAD,'request',RESPONSE,'release','failed:response:response:cleanup','count:1']),
 ('unchanged-retry',7,b'"original"',2,[PAYLOAD,'request','sleep','request',RESPONSE,'accepted','body:ok','count:2']),
 ('nonfinite-replacement',8,None,0,[PAYLOAD,'failed:request:nonfinite','count:0']),
 ('null',9,b'null',1,[PAYLOAD,'request',RESPONSE,'accepted','body:ok','count:1']),
 ('invalid-url',10,None,0,[PAYLOAD,'failed:request:url','count:0']),
 ('invalid-timeout',11,None,0,[PAYLOAD,'failed:request:headers','count:0']),
]

def serve(listener,body,count):
    peers=[]
    for index in range(count):
        peer,_=listener.accept()
        with peer:
            peer.settimeout(5)
            raw=b''
            while b'\r\n\r\n' not in raw:
                part=peer.recv(4096);assert part,'EOF before head';raw+=part
                assert len(raw)<65536
            head,data=raw.split(b'\r\n\r\n',1)
            lines=head.split(b'\r\n')
            assert lines[0]==b'POST /v1/responses HTTP/1.1',lines[0]
            fields={key.lower():value.strip() for key,value in (line.split(b':',1) for line in lines[1:])}
            assert fields[b'host']==b'127.0.0.1:'+str(listener.getsockname()[1]).encode(),fields
            assert fields[b'authorization']==b'Bearer fixture-key',fields
            assert fields[b'content-type']==b'application/json',fields
            assert fields[b'x-stainless-retry-count']==b'0',fields
            assert int(fields[b'content-length'])==len(body),fields
            while len(data)<len(body):
                part=peer.recv(4096);assert part,'EOF before body';data+=part
            assert data==body,(data,body)
            wire=(b'HTTP/1.1 429 Busy\r\nretry-after-ms: 1\r\nContent-Length: 4\r\n\r\nbusy' if index+1<count else b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok')
            peer.sendall(wire);peer.shutdown(socket.SHUT_WR)
            try: assert peer.recv(4096)==b'';closed='eof'
            except ConnectionResetError: closed='reset'
            peers.append(dict(body=data.decode(),closed=closed))
    return peers

def audited(stderr,backend,count):
    lines=stderr.strip().splitlines()
    assert len(lines)==(3 if backend=='bun' else 1),stderr
    values=list(map(int,next(line for line in lines if line.startswith('RESOURCES ')).split()[1:]))
    expected=3 if count==2 else count
    assert len(values)==(7 if backend=='bun' else 11),stderr
    assert values[:2]==[expected,int(count>0)] and not any(values[2:]),stderr
    if backend=='bun': assert 'AUDIT 0 0 0' in lines and 'UDP 0 0' in lines,stderr
    return values

backends=[('bun',[BUN,str(PREFIX)+'.js'])] if any(arg in sys.argv for arg in ['--js-only','--js-audit']) else [('native-1',[str(PREFIX),'--threads','1']),('native-4',[str(PREFIX),'--threads','4']),('bun',[BUN,str(PREFIX)+'.js'])]
results=[]
for instrumented in ([True] if '--js-audit' in sys.argv else [False] if '--js-only' in sys.argv else [False,True]):
    for backend,base in backends:
        command=list(base)
        if instrumented:
            command[1 if backend=='bun' else 0]=str(PREFIX)+('-audit.js' if backend=='bun' else '-audit')
        for name,mode,body,count,wanted in CASES:
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen(4);listener.settimeout(5)
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future=pool.submit(serve,listener,body,count)
                    run=subprocess.run([*command,str(mode),str(listener.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=20)
                    assert run.returncode==0,(backend,name,run.stdout,run.stderr)
                    peers=future.result(timeout=6)
                assert run.stdout.splitlines()==wanted,(backend,name,run.stdout,run.stderr,wanted)
                resources=audited(run.stderr,backend,count) if instrumented else None
                if not instrumented:assert not run.stderr,run.stderr
                listener.settimeout(.025)
                try:
                    extra,_=listener.accept();extra.close();raise AssertionError('unexpected extra connection')
                except TimeoutError: pass
                results.append(dict(backend=backend,instrumented=instrumented,case=name,peers=peers,resources=resources))
        print(backend,'audited' if instrumented else 'production',len(CASES),'hook/envelope/native attempt cases PASS',flush=True)

pending=[ROOT/'tests/openai-responses-acquire.bend'];visited=set()
while pending:
    path=pending.pop().resolve()
    if path in visited: continue
    visited.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
visited.update([Path(__file__).resolve(),ROOT/'tests/transport_audit.py',ROOT/'tests/channel_audit.py'])
programs=[Path(arg) for _,command in backends for arg in command if str(PREFIX) in arg]
if '--js-only' not in sys.argv:programs.extend(Path(str(PREFIX)+suffix) for suffix in (['-audit.js'] if '--js-audit' in sys.argv else ['-audit','-audit.js']))
record=dict(scope='Actual native cleartext fetch and owned native request callback composed with canonical envelope serialization, payload/response hooks, provider retry and native sleep. Complete upload bytes and peer release verified. Request callback factories are disposed before consuming a returned successful body. Cleanup failure is injected after real body release. Generic bridge preserves caller-supplied typed errors; this fixture renders errors as strings. No TLS or completed provider/session claim.',sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(visited)},programs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(programs))},samples=results)
Path(str(PREFIX)+('-js-audit-result.json' if '--js-audit' in sys.argv else '-js-result.json' if '--js-only' in sys.argv else '-result.json')).write_text(json.dumps(record,indent=2)+'\n')
