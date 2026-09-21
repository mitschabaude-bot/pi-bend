"""Real loopback checks for the native Responses cleartext callback."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib, json, re, socket, subprocess, sys, time
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
bun = Path.home()/'.bun/bin/bun'
prefix = ROOT/'build/openai-responses-cleartext-fetch'
SOURCE = 'tests/openai-responses-cleartext-fetch.bend'

def replace_once(source, before, after):
    assert source.count(before) == 1, before
    return source.replace(before, after)

if '--no-build' in sys.argv:
    previous=json.loads(Path(f'{prefix}-result.json').read_text())
    for path,digest in previous['sources'].items():
        if Path(path)!=Path(__file__).resolve():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path
    for path,digest in previous['programs'].items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path

if '--no-build' not in sys.argv:
    for suffix in ['c', 'js']:
        with Path(f'{prefix}-{suffix}.log').open('w') as log:
            subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '16' if suffix=='c' else '12', '--stats', f'{prefix}-{suffix}-build.json', '--', str(bun), str(candidate/'main.ts'), SOURCE, '-o', f'{prefix}.{suffix}'], cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    c = Path(f'{prefix}.c').read_text()
    original = (candidate / 'effs/timer.c').read_text()
    changed = 'static unsigned probe_created,probe_live,probe_peak;\n' + original
    changed = replace_once(changed, '  row->gen += 1;', '  probe_created++; probe_live++; if(probe_live>probe_peak)probe_peak=probe_live;\n  row->gen += 1;')
    changed = replace_once(changed, '  row->live = 0;', '  probe_live--;\n  row->live = 0;')
    audit = r'''
    static void __attribute__((destructor)) attempt_audit(void) {
     unsigned timers=0,waiters=0,channels=0,connects=0,fds=0,sockets=0,udp=0;
     for(u32 i=0;i<udp_read_len;i++)udp+=udp_read_rows[i].live;
     for(u32 i=0;i<udp_write_len;i++)udp+=udp_write_rows[i].live;
     for(u32 i=0;i<timer_len;i++){timers+=timer_rows[i].live;waiters+=timer_rows[i].waiter!=NULL;}
     for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
     for(u32 i=0;i<connect_len;i++){connects+=connect_rows[i].live;fds+=connect_rows[i].fd>=0;waiters+=connect_rows[i].waiter!=NULL;}
     for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
     fprintf(stderr,"RESOURCES %u %u %u %u %u %u %u %u %u %u %u\n",probe_created,probe_peak,probe_live,timers,waiters,channels,connects,fds,sockets,io_park.head!=NULL,udp);
    }
    '''
    Path(f'{prefix}-audit.c').write_text(replace_once(c, original, changed) + audit)
    for suffix in ['', '-audit']:
        subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c', '-lpthread', '-lm', '-o', f'{prefix}{suffix}'], check=True)
    js = Path(f'{prefix}.js').read_text()
    original = (candidate / 'effs/timer.js').read_text()
    changed = original
    changed = replace_once(changed, 'function timer_new(ms) {', 'function timer_new(ms) { probeCreated++;probeLive++;probePeak=Math.max(probePeak,probeLive);')
    # Keep rows only in this audited fixture; production effects are unchanged.
    changed = replace_once(changed, '  row.state = 3;', '  probeLive--;\n  row.state = 3;')
    needle = '  return io_tup(row, row);'
    # Native effect and Bun have different wrappers; use the actual return form.
    if needle not in changed:
        needle = '  return io_done(io_tup(row, row));'
    changed = replace_once(changed, needle, '  probeTimers.push(row);\n' + needle)
    js = replace_once(js, original, changed)
    original = (candidate / 'effs/connect.js').read_text()
    changed = original
    changed = replace_once(changed, 'return io_done(io_tup(row, row));', 'probeConnects.push(row); return io_done(io_tup(row, row));')
    js = replace_once(js, original, changed)
    js = "const probeTimers=[],probeConnects=[];let probeCreated=0,probeLive=0,probePeak=0;\nprocess.on('exit',()=>console.error('RESOURCES',probeCreated,probePeak,probeLive,probeTimers.filter(x=>x.state!==3).length,probeTimers.filter(x=>x.waiter!==null).length+probeConnects.filter(x=>x.waiter!==null).length,probeConnects.filter(x=>x.state!==3).length,probeConnects.filter(x=>x.fd>=0).length));\n" + js
    Path(f'{prefix}-audit.js').write_text(instrument(js))

cases = [
    ('fixed',0,b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabcdef',['head:200','body:abcdef']),
    ('informational',0,b'HTTP/1.1 103 Early\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabcdef',['head:200','body:abcdef']),
    ('chunked',0,b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n4\r\ncdef\r\n0\r\nX-End: yes\r\n\r\n',['head:200','body:abcdef']),
    ('slow-body',0,b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n',['head:200','body:abcdef']),
    ('early-close',1,b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n',['head:200','closed']),
    ('cancel',2,b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n',['head:200','abort:stop']),
    ('truncated',0,b'HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nabcdef',['head:200','body-error']),
    ('bad-head',0,b'broken\r\n\r\n',['header-error']),
    ('timeout',4,b'',['timeout']),
    ('status-error',0,b'HTTP/1.1 429 Busy\r\nContent-Length: 6\r\n\r\nabcdef',['head:429','body:abcdef']),
]
results=[]

def execute(command, arguments, audited, backend):
    result=subprocess.run([*command,*map(str,arguments)],cwd=ROOT,capture_output=True,text=True,timeout=20)
    assert result.returncode==0,(backend,arguments,result.stdout,result.stderr)
    resources=None
    if audited:
        lines=result.stderr.strip().splitlines()
        resources=list(map(int,next(x for x in lines if x.startswith('RESOURCES ')).split()[1:]))
        assert len(resources)==(7 if backend=='bun' else 11),resources
        expected_timers=2 if arguments[0]==1 else 1
        assert resources[:2]==[expected_timers,expected_timers] and not any(resources[2:]),(backend,arguments,resources)
        if backend=='bun':assert 'AUDIT 0 0 0' in lines and len(lines)==2,result.stderr
        else:assert len(lines)==1,result.stderr
    else:assert not result.stderr,result.stderr
    return result.stdout.splitlines(),resources

for audited in [False,True]:
    suffix='-audit' if audited else ''
    for backend,command in [('native-1',[f'{prefix}{suffix}','--threads','1']),('native-4',[f'{prefix}{suffix}','--threads','4']),('bun',[str(bun),f'{prefix}{suffix}.js'])]:
        for family in [4,6]:
            af,address=(socket.AF_INET,'127.0.0.1') if family==4 else (socket.AF_INET6,'::1')
            # Hosts routing shares the same complete request/body path.
            for route in [0,1]:
                for name,flow,wire,expected in cases:
                    # Exercise the full protocol matrix numerically and a normal
                    # exchange through each hosts-family route.
                    if route==1 and name!='fixed':continue
                    with socket.socket(af) as listener:
                        listener.bind((address,0)); listener.listen(); listener.settimeout(10)
                        port=listener.getsockname()[1]
                        authority=(f'[{address}]' if family==6 else address) if route==0 else 'unit'
                        authority+=f':{port}'
                        def serve():
                            with listener.accept()[0] as peer:
                                peer.settimeout(10)
                                request=b''
                                while b'\r\n\r\n' not in request:
                                    chunk=peer.recv(4096);assert chunk,'incomplete head';request+=chunk
                                head,payload=request.split(b'\r\n\r\n',1)
                                lines=head.decode('ascii').split('\r\n')
                                assert lines[0]=='POST /responses?x=1 HTTP/1.1',lines
                                headers=dict(line.lower().split(': ',1) for line in lines[1:])
                                assert headers['host']==authority and headers['x-fixture']=='yes',headers
                                length=int(headers['content-length'])
                                while len(payload)<length:
                                    chunk=peer.recv(4096);assert chunk,'incomplete body';payload+=chunk
                                assert payload=='{"message":"héllo"}'.encode() and len(payload)==length,payload
                                if wire:peer.sendall(wire)
                                if name=='slow-body':
                                    time.sleep(1.25)
                                    peer.sendall(b'abcdef')
                                if flow==0:peer.shutdown(socket.SHUT_WR)
                                assert peer.recv(4096)==b'','owner did not close or wrote extra bytes'
                                return dict(request_verified=True,peer_closed=True)
                        with ThreadPoolExecutor(max_workers=1) as pool:
                            peer=pool.submit(serve)
                            output,resources=execute(command,[route,family,port,flow],audited,backend)
                            observation=peer.result(timeout=12)
                        assert output==expected,(backend,family,route,name,output,expected)
                    results.append(dict(backend=backend,audited=audited,family=family,route=route,case=name,resources=resources,**observation))
            output,resources=execute(command,[3,family,9,0],audited,backend)
            assert output==['tls-required'],output
            results.append(dict(backend=backend,audited=audited,family=family,case='tls-required',resources=resources))
        print(backend,'audited' if audited else 'unmodified','PASS',flush=True)

pending=[ROOT/SOURCE];sources={}
while pending:
    path=pending.pop().resolve()
    if str(path) in sources:continue
    sources[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    pending += [path.parent/name for name in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.MULTILINE)]
for path in [Path(__file__).resolve(),ROOT/'tests/channel_audit.py',candidate/'main.ts',candidate/'base.bend',*sorted((candidate/'effs').glob('*.c')),*sorted((candidate/'effs').glob('*.js'))]:
    sources[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
Path(f'{prefix}-result.json').write_text(json.dumps(dict(scope='Loopback native Responses callback; IPv4/IPv6, numeric/hosts, wire request checks, response framing, headers-only timeout, cancellation, early close, typed failures and cleartext TLS rejection. Native timer/channel/connection/UDP/socket audits and Bun timer/connection/channel audits. No TLS implementation, live provider or end-to-end agent claim.',sources=sources,programs={str(Path(f'{prefix}{suffix}')):hashlib.sha256(Path(f'{prefix}{suffix}').read_bytes()).hexdigest() for suffix in ('','.c','.js','-audit','-audit.c','-audit.js')},runs=results),indent=2)+'\n')
