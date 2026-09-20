"""Live UDP-to-TCP DNS switching preserves the request, selected pass and total deadline."""
import argparse
import hashlib
import json
import re
import select
import shutil
import socket
import struct
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate', type=Path)
p.add_argument('--c-input', type=Path)
a = p.parse_args()
candidate = a.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
for suffix in ['c', 'js']:
    if suffix == 'c' and a.c_input:
        shutil.copyfile(a.c_input, ROOT / 'build/dns-transport.c')
        continue
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                    '--stats', f'build/dns-transport-{suffix}-build.json', '--',
                    str(bun), str(candidate / 'main.ts'), 'tests/dns-transport.bend',
                    '-o', f'build/dns-transport.{suffix}'], cwd=ROOT, check=True)

source = (ROOT / 'build/dns-transport.c').read_text()
needle = 'static Term connect_start(Env e, int family, const struct sockaddr* address, socklen_t length) {'
assert source.count(needle) == 1
source = source.replace(needle, 'static void transport_before_connect(void);\n' + needle + '\n transport_before_connect();')
source += '''
static void transport_counts(unsigned *r,unsigned *w,unsigned *t,unsigned *c,unsigned *s,unsigned *k) {
 *r=*w=*t=*c=*s=*k=0;
 for(u32 i=0;i<udp_read_len;i++)*r+=udp_read_rows[i].live;
 for(u32 i=0;i<udp_write_len;i++)*w+=udp_write_rows[i].live;
 for(u32 i=0;i<timer_len;i++)*t+=timer_rows[i].live;
 for(u32 i=0;i<chan_len;i++)*c+=chan_rows[i].live;
 for(u32 i=0;i<connect_len;i++)*k+=connect_rows[i].live;
 for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)(*s)++;}
}
static void transport_before_connect(void) {
 unsigned r,w,t,c,s,k;transport_counts(&r,&w,&t,&c,&s,&k);
 if(r||w||s||k||t>1){fprintf(stderr,"UNCLEAN SWITCH %u %u %u %u %u\\n",r,w,t,s,k);abort();}
}
static void __attribute__((destructor)) transport_exit(void) {
 unsigned r,w,t,c,s,k;transport_counts(&r,&w,&t,&c,&s,&k);
 fprintf(stderr,"AUDIT %u %u %u %u %u %u %u\\n",r,w,t,c,s,k,io_park.head!=NULL);
}
'''
(ROOT / 'build/dns-transport-audit.c').write_text(source)
subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                'build/dns-transport-audit.c', '-lpthread', '-lm',
                '-o', 'build/dns-transport'], cwd=ROOT, check=True)
(ROOT / 'build/dns-transport-audit.js').write_text(
    'process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'
    + (ROOT / 'build/dns-transport.js').read_text())

query = struct.pack('!6H', 42, 256, 1, 0, 0, 0) + b'\0\0\1\0\1'
def response(flags=0x8180, ident=42):
    return struct.pack('!6H', ident, flags, 1, 0, 0, 0) + query[12:]
def exact(peer, count):
    data = b''
    while len(data) < count:
        chunk = peer.recv(count - len(data))
        assert chunk, 'early query EOF'
        data += chunk
    return data

modes = ['normal', 'direct', 'edns', 'tcp-next', 'last', 'duplicate', 'rotation',
         'round', 'rcode', 'truncated', 'refused', 'reset', 'reset-exhausted',
         'partial', 'noise', 'total', 'later', 'size', 'zero', 'pre', 'invalid']
rows = []
for backend, command in [('native 1', ['build/dns-transport', '--threads', '1']),
                         ('native 4', ['build/dns-transport', '--threads', '4']),
                         ('Bun', [str(bun), 'build/dns-transport-audit.js'])]:
    for family, af, host in [(4, socket.AF_INET, '127.0.0.1'), (6, socket.AF_INET6, '::1')]:
        for mode in modes:
            udp, tcp, held = [], [], []
            process = None
            try:
                for _ in range(3):
                    listener = socket.socket(af, socket.SOCK_STREAM)
                    listener.bind((host, 0)); listener.listen()
                    datagram = socket.socket(af, socket.SOCK_DGRAM)
                    datagram.bind((host, listener.getsockname()[1]))
                    tcp.append(listener); udp.append(datagram)
                ports = [peer.getsockname()[1] for peer in udp]
                if mode == 'refused': tcp[0].close()
                started = time.monotonic()
                process = subprocess.Popen([*command, str(family), *map(str, ports), mode], cwd=ROOT,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                trace = []
                expected_query = query if mode != 'edns' else query[:10] + b'\0\1' + query[12:] + b'\0\0\x29\x04\xd0' + b'\0'*6
                while process.poll() is None:
                    assert time.monotonic()-started < 9, (backend, family, mode, 'hung', trace)
                    ready, _, _ = select.select([s for s in udp+tcp if s.fileno() >= 0], [], [], .01)
                    for peer in ready:
                        if peer in udp:
                            index = udp.index(peer)
                            wire, client = peer.recvfrom(65536)
                            trace.append(('udp', index))
                            assert wire == expected_query, (mode, 'udp bytes', wire.hex())
                            number = len([x for x in trace if x[0] == 'udp'])
                            reject = mode in ['last', 'duplicate', 'rotation'] and number == 1 or mode == 'round' and number <= 2
                            flags = 0x8182 if reject else 0x8180 if mode == 'direct' else 0x8380
                            if mode == 'total': time.sleep(.8)
                            peer.sendto(response(flags), client)
                        else:
                            index = tcp.index(peer)
                            client, _ = peer.accept(); client.settimeout(2)
                            held.append(client); trace.append(('tcp', index))
                            count = struct.unpack('!H', exact(client, 2))[0]
                            assert exact(client, count) == expected_query, (mode, 'tcp bytes')
                            number = len([x for x in trace if x[0] == 'tcp'])
                            close = mode in ['tcp-next', 'last', 'duplicate', 'rotation', 'round'] and number == 1
                            reset = mode == 'reset' and number == 1 or mode == 'reset-exhausted' and number <= 2
                            if reset:
                                client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0)); client.close()
                            elif close: client.close()
                            elif mode == 'partial' and number == 1:
                                client.sendall(b'\0'); client.close()
                            elif mode not in ['total', 'later']:
                                flags = 0x8182 if mode == 'rcode' else 0x8380 if mode == 'truncated' else 0x8180
                                if mode == 'noise':
                                    bad = response(ident=43); client.sendall(struct.pack('!H', len(bad)) + bad)
                                answer = response(flags)
                                client.sendall(struct.pack('!H', len(answer)) + answer)
                out, err = process.communicate(timeout=1)
                expected_trace = {
                    'direct': [('udp',0)], 'tcp-next': [('udp',0),('tcp',0),('tcp',1)],
                    'last': [('udp',0),('udp',1),('tcp',1)],
                    'duplicate': [('udp',0),('udp',0),('tcp',0),('tcp',1)],
                    'rotation': [('udp',1),('udp',2),('tcp',2),('tcp',0)],
                    'round': [('udp',0),('udp',1),('udp',0),('tcp',0),('tcp',1)],
                    'refused': [('udp',0),('tcp',1)],
                    'reset': [('udp',0),('tcp',0),('tcp',0)],
                    'reset-exhausted': [('udp',0),('tcp',0),('tcp',0),('tcp',1)],
                    'partial': [('udp',0),('tcp',0),('tcp',1)],
                    'size': [('udp',0)], 'zero': [], 'pre': [], 'invalid': [],
                }.get(mode, [('udp',0),('tcp',0)])
                expected = {'last':'tcp:eof', 'rcode':'answer:33154', 'truncated':'truncated',
                            'total':'tcp:read:expiry', 'later':'tcp:read:parent', 'size':'tcp:zero',
                            'zero':'udp:empty', 'pre':f'udp:{ports[0]}:abort:caller:stop:caller:stop',
                            'invalid':f'udp:{ports[0]}:invalid:active'}.get(mode, 'answer:33152')
                assert trace == expected_trace, (backend, family, mode, trace)
                assert process.returncode == 0 and out.strip() == expected, (backend, family, mode, out, err)
                assert err == ('AUDIT 0 0\n' if backend == 'Bun' else 'AUDIT 0 0 0 0 0 0 0\n'), (mode, err)
                assert not select.select([s for s in udp+tcp if s.fileno() >= 0], [], [], 0)[0], (mode, 'extra traffic')
                elapsed = time.monotonic()-started
                if mode == 'total': assert 1.1 < elapsed < 1.8, elapsed
                rows.append(dict(backend=backend,family=family,mode=mode,trace=trace,result=out.strip(),seconds=elapsed,audit=err.strip()))
            finally:
                if process is not None and process.poll() is None: process.kill(); process.wait()
                for peer in udp+tcp+held: peer.close()
    print(f'{backend}: {2*len(modes)} UDP/TCP transport cases PASS', flush=True)

sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/dns-transport.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/dns_transport_check.py']
record=dict(scope=__doc__,candidate=str(candidate),c_input=str(a.c_input) if a.c_input else None,runs=rows,
            sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},
            compiler_sha256={p:hashlib.sha256((candidate/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']})
(ROOT/'build/dns-transport-result.json').write_text(json.dumps(record,indent=2)+'\n')
