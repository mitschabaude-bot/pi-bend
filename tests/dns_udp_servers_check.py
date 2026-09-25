"""Ordered UDP DNS attempts share one total deadline and retire owned resources."""
import os
import hashlib
import json
import re
import select
import socket
import struct
import subprocess
import time
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN

ROOT = Path(__file__).resolve().parents[1]
BUN = Path.home() / '.bun/bin/bun'
CANDIDATE = Path(os.environ.get('BEND_CANDIDATE', TOOLCHAIN))

for suffix in ['c', 'js']:
    subprocess.run([
        'python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8',
        '--stats', f'build/dns-udp-servers-{suffix}-build.json', '--',
        str(BUN), str(CANDIDATE / 'main.ts'), 'tests/dns-udp-servers.bend',
        '-o', f'build/dns-udp-servers.{suffix}',
    ], cwd=ROOT, check=True)

# Test-only instrumentation. At every bind, the preceding attempt must have
# retired its datagram operations/socket and its timer. Total + new child = 2.
audit = '''
static unsigned servers_attempts=0;
static void servers_counts(unsigned *r,unsigned *w,unsigned *t,unsigned *c,unsigned *s) {
  *r=*w=*t=*c=*s=0;
  for(u32 i=0;i<udp_read_len;i++)*r+=udp_read_rows[i].live;
  for(u32 i=0;i<udp_write_len;i++)*w+=udp_write_rows[i].live;
  for(u32 i=0;i<timer_len;i++)*t+=timer_rows[i].live;
  for(u32 i=0;i<chan_len;i++)*c+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)(*s)++;}
}
static void servers_before_bind(void) {
  unsigned r,w,t,c,s; servers_counts(&r,&w,&t,&c,&s);
  servers_attempts++;
  if(r||w||s||t>2){fprintf(stderr,"UNCLEAN ATTEMPT %u %u %u %u\\n",r,w,t,s);abort();}
}
static void __attribute__((destructor)) servers_exit(void) {
  unsigned r,w,t,c,s; servers_counts(&r,&w,&t,&c,&s);
  fprintf(stderr,"AUDIT %u %u %u %u %u %u\\n",r,w,t,c,s,io_park.head!=NULL);
  fprintf(stderr,"ATTEMPTS %u\\n",servers_attempts);
}
'''
source = (ROOT / 'build/dns-udp-servers.c').read_text()
needle = 'Term udp_bind_family_run(Env e, Term* f, IoWork* w) {'
assert source.count(needle) == 1
source = source.replace(needle, 'static void servers_before_bind(void);\n' + needle + '\n  servers_before_bind();')
(ROOT / 'build/dns-udp-servers-audit.c').write_text(source + audit)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                'build/dns-udp-servers-audit.c', '-lpthread', '-lm',
                '-o', 'build/dns-udp-servers'], cwd=ROOT, check=True)
js_source = (ROOT / 'build/dns-udp-servers.js').read_text()
js_needle = 'function udp_bind_family(family, port) {'
assert js_source.count(js_needle) == 1
js_source = js_source.replace(js_needle, js_needle + '\n  servers_attempts++;')
(ROOT / 'build/dns-udp-servers-audit.js').write_text(
    'let servers_attempts=0;\n'
    'process.on("exit",()=>console.error(`AUDIT ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}\\nATTEMPTS ${servers_attempts}`));\n'
    + js_source)

query = struct.pack('!6H', 42, 256, 1, 0, 0, 0) + b'\0\0\1\0\1'
modes = ['badvers', 'extended-servfail', 'extended-refused', 'opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short', 'opt-version', 'servfail', 'notimp', 'rcode-refused', 'empty-answer', 'rcode-tc', 'all-rcode', 'nxdomain', 'first', 'second', 'round', 'exhausted', 'duplicate', 'rotation',
         'refused', 'all-refused', 'truncated', 'total', 'later', 'pre',
         'pre-default', 'zero', 'empty', 'budget', 'port', 'invalid']
rows = []
for backend, command in [
    ('native 1', ['build/dns-udp-servers', '--threads', '1']),
    ('native 4', ['build/dns-udp-servers', '--threads', '4']),
    ('Bun', [str(BUN), 'build/dns-udp-servers-audit.js']),
]:
    for family, af, host in [(4, socket.AF_INET, '127.0.0.1'), (6, socket.AF_INET6, '::1')]:
        for mode in modes:
            peers = [socket.socket(af, socket.SOCK_DGRAM) for _ in range(3)]
            process = None
            try:
                for peer in peers:
                    peer.bind((host, 0))
                ports = [peer.getsockname()[1] for peer in peers]
                if mode in ['refused', 'all-refused']:
                    peers[0].close()
                if mode == 'all-refused':
                    peers[1].close()
                started = time.monotonic()
                process = subprocess.Popen([*command, str(family), *map(str, ports), mode],
                                           cwd=ROOT, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True)
                received = []
                while process.poll() is None:
                    assert time.monotonic() - started < 9, (backend, family, mode, 'hung')
                    ready, _, _ = select.select([p for p in peers if p.fileno() >= 0], [], [], .01)
                    for peer in ready:
                        wire, client = peer.recvfrom(65536)
                        index = peers.index(peer)
                        received.append((index, time.monotonic() - started))
                        expected_query = query[:10] + b'\0\1' + query[12:] + b'\0\0\x29\x04\xd0' + bytes(6) if mode in ['badvers', 'extended-servfail', 'extended-refused', 'opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short', 'opt-version'] else query
                        assert wire == expected_query, (mode, wire.hex())
                        respond = (
                            mode in ['badvers', 'extended-servfail', 'extended-refused', 'opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short', 'opt-version', 'servfail', 'notimp', 'rcode-refused', 'empty-answer', 'rcode-tc', 'all-rcode', 'nxdomain', 'first', 'truncated', 'refused'] or
                            mode in ['second', 'rotation'] and len(received) == 2 or
                            mode == 'round' and len(received) == 3 or
                            mode == 'duplicate' and len(received) == 2
                        )
                        if respond:
                            flags = 0x8380 if mode == 'truncated' else 0x8180
                            if mode == 'all-rcode' or len(received) == 1:
                                flags = {'servfail': 0x8182, 'notimp': 0x8184, 'rcode-refused': 0x8185, 'empty-answer': 0x8100, 'rcode-tc': 0x8382, 'all-rcode': 0x8185, 'nxdomain': 0x8183}.get(mode, flags)
                            if mode in ['badvers', 'extended-servfail', 'extended-refused', 'opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short', 'opt-version']:
                                flags = {'extended-servfail': 0x8182, 'extended-refused': 0x8185}.get(mode, 0x8180)
                                ttl = 1 << 24 if mode in ['badvers', 'extended-servfail', 'extended-refused'] else (7 << 16) | 0x7fff if mode == 'opt-version' else 0
                                owner = b'\x01a\0' if mode == 'opt-owner' else b'\0'
                                data = b'\x2a' if mode == 'opt-short' else b''
                                opt = owner + struct.pack('!HHIH', 41, 1232, ttl, len(data)) + data
                                if mode == 'opt-duplicate': opt += opt
                                wire = struct.pack('!6H', 42, flags, 1, int(mode == 'opt-misplaced'), 0, 0 if mode == 'opt-misplaced' else 2 if mode == 'opt-duplicate' else 1) + query[12:] + opt
                            else:
                                wire = struct.pack('!6H', 42, flags, 1, 0, 0, 0) + query[12:]
                            peer.sendto(wire, client)
                out, err = process.communicate(timeout=1)
                elapsed = time.monotonic() - started
                expected_order = {
                    **{name:[0] for name in ['badvers', 'extended-servfail', 'extended-refused', 'opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short', 'opt-version']},
                    'servfail': [0, 1], 'notimp': [0, 1], 'rcode-refused': [0, 1], 'empty-answer': [0, 1], 'rcode-tc': [0, 1], 'all-rcode': [0, 1, 0, 1], 'nxdomain': [0],
                    'first': [0], 'second': [0, 1], 'round': [0, 1, 0],
                    'exhausted': [0, 1, 0, 1], 'duplicate': [0, 0],
                    'rotation': [1, 2], 'refused': [1], 'all-refused': [],
                    'truncated': [0], 'total': [0, 1], 'later': [0],
                }.get(mode, [])
                assert [i for i, _ in received] == expected_order, (backend, family, mode, received)
                if mode in ['servfail', 'notimp', 'rcode-refused', 'empty-answer', 'rcode-tc', 'first', 'second', 'round', 'duplicate', 'rotation', 'refused']:
                    expected = f'{ports[expected_order[-1]]}:answer:33152:17:1'
                elif mode == 'all-rcode':
                    expected = f'{ports[1]}:rejected:33157:active'
                elif mode == 'nxdomain':
                    expected = f'{ports[0]}:answer:33155:17:1'
                elif mode in ['badvers', 'extended-servfail', 'extended-refused', 'opt-version']:
                    expected = f'{ports[0]}:answer:{flags}:28:0'
                elif mode in ['opt-duplicate', 'opt-misplaced', 'opt-owner', 'opt-short']:
                    expected = f'{ports[0]}:extension:active'
                elif mode == 'truncated':
                    expected = f'{ports[0]}:truncated'
                elif mode in ['zero', 'empty']:
                    expected = 'empty'
                elif mode == 'port':
                    expected = '0:destination:active'
                elif mode in ['budget', 'invalid']:
                    expected = f'{ports[0]}:{mode}:active'
                elif mode == 'exhausted':
                    expected = f'{ports[1]}:abort:attempt:attempt'
                elif mode == 'all-refused':
                    expected = f'{ports[1]}:socket:111:active'
                elif mode == 'total':
                    expected = f'{ports[1]}:abort:total:total'
                else:
                    why = 'default' if mode == 'pre-default' else 'stop'
                    expected = f'{ports[0]}:abort:caller:{why}:caller:{why}'
                assert process.returncode == 0 and out.strip() == expected, (backend, family, mode, out, err)
                expected_attempts = 4 if mode == 'all-refused' else 2 if mode == 'refused' else len(expected_order)
                expected_audit = ('AUDIT 0 0\n' if backend == 'Bun' else 'AUDIT 0 0 0 0 0 0\n') + f'ATTEMPTS {expected_attempts}\n'
                assert err == expected_audit, (mode, err)
                assert not select.select([p for p in peers if p.fileno() >= 0], [], [], 0)[0], (mode, 'extra query')
                if mode in ['second', 'duplicate', 'rotation']:
                    # Rotation starts at original second-of-three: floor(2*2/3)=1s.
                    assert .85 < received[1][1] - received[0][1] < 1.7, (mode, received)
                if mode == 'total':
                    assert 1.1 < elapsed < 2.0, elapsed
                rows.append(dict(backend=backend, family=family, mode=mode,
                                 received=received, seconds=elapsed, result=out.strip(), audit=err.strip()))
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
                for peer in peers:
                    peer.close()
    print(f'{backend}: {2 * len(modes)} multi-server attempts PASS', flush=True)

sources = set()
def imports(path):
    path = path.resolve()
    if path in sources:
        return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M):
        imports(path.parent / relative)
imports(ROOT / 'tests/dns-udp-servers.bend')
paths = sorted(str(p.relative_to(ROOT)) for p in sources) + ['tests/dns_udp_servers_check.py']
record = dict(scope=__doc__, runs=rows,
              sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths},
              compiler_sha256={p: hashlib.sha256((CANDIDATE / p).read_bytes()).hexdigest()
                               for p in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
              builds={s: json.loads((ROOT / f'build/dns-udp-servers-{s}-build.json').read_text())
                      for s in ['c', 'js']})
(ROOT / 'build/dns-udp-servers-result.json').write_text(json.dumps(record, indent=2) + '\n')
