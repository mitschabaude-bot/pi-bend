"""Real native HTTP attempts under the provider retry loop and native sleep.

The loopback server checks uploads and peer release before accepting a retry.
Production networking, classification, diagnostics and backoff are all Bend.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import re
import socket
import struct
import subprocess
import sys
import time
from threading import Event

ROOT = Path(__file__).resolve().parents[1]
BUN = str(Path.home()/'.bun/bin/bun')
PREFIX = ROOT/'build/openai-responses-cleartext-attempt'
SOURCE = ROOT/'tests/openai-responses-cleartext-attempt.bend'

BUSY = b'{"error":{"message":"busy"}}'
BODY = '{"message":"héllo"}'.encode()

def reply(status=200, body=b'ok', headers=b''):
    return b'HTTP/1.1 '+str(status).encode()+b' Status\r\nContent-Length: '+str(len(body)).encode()+b'\r\n'+headers+b'\r\n'+body

# name, route, timeout, cap, pre-abort, responses, expected trace, timers, peak
CASES = [
 ('success',0,1000,65536,False,[reply()],['request','success','body:ok','count:1'],1,1),
 ('retry-429',0,1000,65536,False,[reply(429,BUSY,b'retry-after-ms: 1\r\n'),reply()],['request','sleep','request','success','body:ok','count:2'],3,1),
 ('terminal-400',0,1000,65536,False,[reply(400,BUSY)],['request','provider:http:400 busy:400 busy','count:1'],1,1),
 ('retry-400-hint',0,1000,65536,False,[reply(400,BUSY,b'x-should-retry: true\r\nretry-after-ms: 1\r\n'),reply()],['request','sleep','request','success','body:ok','count:2'],3,1),
 ('stop-429-hint',0,1000,65536,False,[reply(429,BUSY,b'x-should-retry: false\r\n')],['request','provider:http:429 busy:429 busy','count:1'],1,1),
 ('malformed-head',0,1000,65536,False,[b'broken\r\n\r\n',reply()],['request','random','sleep','request','success','body:ok','count:2'],3,1),
 ('timeout',0,50,65536,False,[None,reply()],['request','random','sleep','request','success','body:ok','count:2'],3,1),
 ('truncated-diagnostic',0,1000,65536,False,[b'HTTP/1.1 429 Busy\r\nContent-Length: 100\r\nretry-after-ms: 1\r\n\r\nbad',reply()],['request','sleep','request','success','body:ok','count:2'],3,1),
 ('invalid-utf8-diagnostic',0,1000,65536,False,[reply(429,b'\xff',b'retry-after-ms: 1\r\n'),reply()],['request','sleep','request','success','body:ok','count:2'],3,1),
 ('bounded-diagnostic',0,1000,1,False,[reply(429,BUSY,b'x-should-retry: false\r\n')],['request','provider:diagnostic:Could not read the error response diagnostic.','count:1'],1,1),
 ('delay-cap',0,1000,65536,False,[reply(429,BUSY,b'retry-after-ms: 70000\r\n')],['request','delay-rejected','count:1'],1,1),
 ('hosts',1,1000,65536,False,[reply()],['request','success','body:ok','count:1'],2,2),
 ('hosts-source-error',2,1000,65536,False,[],['request','other:fetch','count:1'],1,1),
 ('tls-rejected',3,1000,65536,False,[],['request','other:fetch','count:1'],1,1),
 ('invalid-read-size',5,1000,65536,False,[],['request','other:fetch','count:1'],1,1),
 ('pre-abort',0,1000,65536,True,[],['request','aborted','count:1'],0,0),
]

def request_bytes(peer, port, route):
    raw=b''
    while b'\r\n\r\n' not in raw:
        part=peer.recv(4096)
        assert part,'EOF before request head'
        raw+=part
        assert len(raw)<65536
    header,body=raw.split(b'\r\n\r\n',1)
    lines=header.split(b'\r\n')
    assert lines[0]==b'POST /responses?x=1 HTTP/1.1',lines[0]
    fields={key.lower():value.strip() for key,value in (line.split(b':',1) for line in lines[1:])}
    host=b'127.0.0.1' if route==0 else b'unit'
    assert fields[b'host']==host+b':'+str(port).encode(),fields
    assert fields[b'x-fixture']==b'yes'
    assert int(fields[b'content-length'])==len(BODY)
    while len(body)<len(BODY):
        part=peer.recv(4096)
        assert part,'EOF before request body'
        body+=part
    assert body==BODY,body
    return len(body)

def serve(listener, wires, route):
    counts=[]
    for wire in wires:
        peer,_=listener.accept()
        with peer:
            peer.settimeout(5)
            count=request_bytes(peer,listener.getsockname()[1],route)
            if wire is not None:
                peer.sendall(wire)
                peer.shutdown(socket.SHUT_WR)
            try:
                assert peer.recv(4096)==b'','unexpected request bytes after body'
                end='eof'
            except ConnectionResetError:
                end='reset'
            counts.append(dict(bytes=count,closed=end))
    return counts

def audit(stderr, backend, timers, peak):
    lines=stderr.strip().splitlines()
    resource=[line for line in lines if line.startswith('RESOURCES ')]
    assert len(resource)==1,stderr
    values=list(map(int,resource[0].split()[1:]))
    assert len(values)==(7 if backend=='bun' else 11),stderr
    assert values[:2]==[timers,peak] and not any(values[2:]),stderr
    assert len(lines)==(3 if backend=='bun' else 1),stderr
    if backend=='bun': assert 'AUDIT 0 0 0' in lines and 'UDP 0 0' in lines,stderr
    return values

def serve_dns(udp, stop, mode):
    questions=[]
    udp.settimeout(.05)
    while not stop.is_set():
        try: query,peer=udp.recvfrom(512)
        except TimeoutError: continue
        assert len(query)==22 and query[12:18]==b'\x04unit\x00',query
        ident,flags,qd,an,ns,ar=struct.unpack('!6H',query[:12])
        kind,klass=struct.unpack('!2H',query[-4:])
        assert (flags,qd,an,ns,ar,klass)==(256,1,0,0,0,1),query
        assert kind in (1,28),query
        questions.append(kind)
        if mode=='nxdomain':
            udp.sendto(struct.pack('!6H',ident,0x8183,1,0,0,0)+query[12:],peer)
    assert sorted(questions)==[1,1,28,28],questions
    return questions

results=[]
backends=[('bun',[BUN,str(PREFIX)+'.js'])] if any(arg in sys.argv for arg in ['--js-only','--js-audit']) else [('native-1',[str(PREFIX),'--threads','1']),('native-4',[str(PREFIX),'--threads','4']),('bun',[BUN,str(PREFIX)+'.js'])]
for instrumented in ([True] if '--js-audit' in sys.argv else [False] if '--js-only' in sys.argv else [False,True]):
    for backend,base in backends:
        command=list(base)
        if instrumented:
            if backend=='bun': command[1]=str(PREFIX)+'-audit.js'
            else: command[0]=str(PREFIX)+'-audit'
        for name,route,timeout,cap,pre,wires,wanted,timers,peak in CASES:
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));listener.listen(4);listener.settimeout(5)
                port=listener.getsockname()[1]
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future=pool.submit(serve,listener,wires,route)
                    start=time.monotonic()
                    run=subprocess.run([*command,str(route),str(port),str(timeout),str(cap),str(int(pre)),'9'],cwd=ROOT,capture_output=True,text=True,timeout=15)
                    peers=future.result(timeout=6)
                seconds=time.monotonic()-start
                assert run.returncode==0,(backend,name,run.stdout,run.stderr)
                assert run.stdout.splitlines()==wanted,(backend,name,run.stdout,wanted,run.stderr)
                residues=audit(run.stderr,backend,timers,peak) if instrumented else None
                if not instrumented: assert not run.stderr,run.stderr
                assert len(peers)==len(wires),(name,peers)
                listener.settimeout(.025)
                try:
                    extra,_=listener.accept();extra.close();raise AssertionError((name,'unexpected connection'))
                except TimeoutError: pass
                if name in ('malformed-head','timeout'): assert seconds>=.4,(name,seconds)
                results.append(dict(backend=backend,instrumented=instrumented,case=name,seconds=seconds,peers=peers,resources=residues))
        for mode in ['nxdomain','timeout']:
            with socket.socket() as listener, socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as udp:
                listener.bind(('127.0.0.1',0));listener.listen(1)
                udp.bind(('127.0.0.1',0))
                stop=Event()
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future=pool.submit(serve_dns,udp,stop,mode)
                    start=time.monotonic()
                    try:
                        run=subprocess.run([*command,'4',str(listener.getsockname()[1]),'1000','65536','0',str(udp.getsockname()[1])],cwd=ROOT,capture_output=True,text=True,timeout=15)
                    finally: stop.set()
                    questions=future.result(timeout=1)
                seconds=time.monotonic()-start
                message='Connection error.' if mode=='nxdomain' else 'Request timed out.'
                wanted=['request','random','sleep','request','provider:fetch:'+message,'count:2']
                assert run.returncode==0 and run.stdout.splitlines()==wanted,(backend,mode,run.stdout,run.stderr)
                # Each attempt owns request + DNS total + A/AAAA attempt timers;
                # the one backoff timer runs only after those four are closed.
                residues=audit(run.stderr,backend,9,4) if instrumented else None
                if not instrumented: assert not run.stderr,run.stderr
                assert seconds>=.4,(mode,seconds)
                listener.settimeout(.025)
                try:
                    extra,_=listener.accept();extra.close();raise AssertionError((mode,'unexpected connection'))
                except TimeoutError: pass
                results.append(dict(backend=backend,instrumented=instrumented,case='dns-'+mode,seconds=seconds,questions=questions,resources=residues))
        print(backend,'audited' if instrumented else 'production',len(CASES)+2,'native request attempts PASS',flush=True)

pending=[SOURCE];visited=set()
while pending:
    path=pending.pop().resolve()
    if path in visited:continue
    visited.add(path)
    pending.extend(path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
visited.update([Path(__file__).resolve(),ROOT/'tests/transport_audit.py',ROOT/'tests/channel_audit.py'])
record=dict(scope='Actual cleartext native transport through attempt classification, owned diagnostic consumption, provider retry and native abortable backoff. Peer closure and upload assertions; resource audits when enabled. Loopback DNS verifies exhausted negative replies and total DNS deadline classification across retries. No TLS implementation or full provider claim.',sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(visited)},samples=results)
programs=[Path(argument) for _,command in backends for argument in command if str(PREFIX) in argument]
if '--js-only' not in sys.argv:
    programs.extend(Path(str(PREFIX)+suffix) for suffix in (['-audit.js'] if '--js-audit' in sys.argv else ['-audit','-audit.js']))
record['programs']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(programs))}
Path(str(PREFIX)+('-js-audit-result.json' if '--js-audit' in sys.argv else '-js-result.json' if '--js-only' in sys.argv else '-result.json')).write_text(json.dumps(record,indent=2)+'\n')
