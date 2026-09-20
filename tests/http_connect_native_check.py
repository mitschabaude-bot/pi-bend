"""Real TCP establishment through typed HTTP numeric/hosts resolution and fallback.

Numeric/hosts paths trap any DNS ID draw. A separate loopback DNS case resolves
both families before real TCP fallback. Full reports and sockets remain owned.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
from pathlib import Path
import select
import socket
import struct
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate', type=Path)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
candidate = args.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
prefix = ROOT / 'build/http-connect-native'

def replace_once(source, before, after):
    assert source.count(before) == 1, before
    return source.replace(before, after)

if not args.no_build:
    for suffix in ['c', 'js']:
        with Path(f'{prefix}-{suffix}.log').open('w') as log:
            subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'{prefix}-{suffix}-build.json', '--', str(bun), str(candidate / 'main.ts'), 'tests/http-connect-native.bend', '-o', f'{prefix}.{suffix}'], cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)

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
results = []

def execute(backend, command, audited, arguments, expected_timers, expected_peak=None):
    result = subprocess.run([*command, *map(str, arguments)], cwd=ROOT, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (backend, arguments, result)
    values = None
    if audited:
        lines = result.stderr.strip().splitlines()
        values = list(map(int, next(x for x in lines if x.startswith('RESOURCES ')).split()[1:]))
        assert len(values) == (7 if backend == "Bun" else 11), values
        assert values[0] == expected_timers and values[1] == (min(1, expected_timers) if expected_peak is None else expected_peak) and not any(values[2:]), (backend, arguments, values)
        if backend == 'Bun':
            assert 'AUDIT 0 0 0' in lines and len(lines) == 2, result.stderr
        else:
            assert len(lines) == 1, result.stderr
    else:
        assert not result.stderr, result.stderr
    results.append(dict(backend=backend, audited=audited, arguments=arguments, resources=values))
    return result.stdout.strip().splitlines()

for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [('native 1', [f'{prefix}{suffix}', '--threads', '1']), ('native 4', [f'{prefix}{suffix}', '--threads', '4']), ('Bun', [str(bun), f'{prefix}{suffix}.js'])]:
        for first_family in [4, 6]:
            first_af, first_host = (socket.AF_INET, '127.0.0.1') if first_family == 4 else (socket.AF_INET6, '::1')
            second_af, second_host = (socket.AF_INET6, '::1') if first_family == 4 else (socket.AF_INET, '127.0.0.1')
            names = ['2130706433', 'ipv6'] if first_family == 4 else ['ipv6', '2130706433']
            for mode in [0, 1, 4]:
                scenarios = ['first-success', 'exhausted'] if mode == 0 else ['first-success', 'refused-fallback', 'timeout-fallback', 'exhausted']
                for scenario in scenarios:
                    with socket.socket(first_af, socket.SOCK_STREAM) as first, socket.socket(second_af, socket.SOCK_STREAM) as second, ThreadPoolExecutor(max_workers=2) as pool:
                        v6 = first if first_af == socket.AF_INET6 else second
                        v6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                        first.bind((first_host, 0)); port = first.getsockname()[1]
                        second.bind((second_host, port))
                        listener = first if scenario == 'first-success' else second
                        future = None
                        if scenario != 'exhausted':
                            listener.listen(1); listener.settimeout(15)
                            def serve():
                                with listener.accept()[0] as peer:
                                    peer.settimeout(10)
                                    assert peer.recv(1) == b''
                            future = pool.submit(serve)
                        filler = None
                        try:
                            if scenario == 'timeout-fallback':
                                first.listen(0)
                                filler = socket.socket(first_af, socket.SOCK_STREAM)
                                filler.settimeout(2); filler.connect(first.getsockname())
                                with socket.socket(first_af, socket.SOCK_STREAM) as probe:
                                    probe.setblocking(False)
                                    assert probe.connect_ex(first.getsockname()) == errno.EINPROGRESS
                                    assert not select.select([], [probe], [], .05)[1]
                            if mode == 4:
                                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as dns:
                                    dns.bind(('127.0.0.1', 0)); dns.settimeout(15)
                                    def answer():
                                        kinds=[]; packets=[]
                                        for _ in range(2):
                                            query, peer = dns.recvfrom(2048)
                                            assert query[12:18] == b'\x04unit\x00', query
                                            kind, klass = struct.unpack('!HH', query[18:22])
                                            assert kind in [1,28] and klass == 1 and len(query) == 22, query
                                            kinds.append(kind)
                                            data = socket.inet_pton(socket.AF_INET if kind == 1 else socket.AF_INET6, '127.0.0.1' if kind == 1 else '::1')
                                            packet = query[:2] + struct.pack('!HHHHH', 0x8180, 1, 1, 0, 0) + query[12:] + b'\xc0\x0c' + struct.pack('!HHIH', kind, 1, 60, len(data)) + data
                                            packets.append((packet,peer))
                                        # Both borrowed query scopes exist before either can finish.
                                        for packet,peer in packets: dns.sendto(packet,peer)
                                        assert sorted(kinds) == [1,28], kinds
                                    dns_future=pool.submit(answer)
                                    output = execute(backend, command, audited, [mode, first_family, port, dns.getsockname()[1]], 4, 3)
                                    dns_future.result(timeout=20)
                            else:
                                output = execute(backend, command, audited, [mode, first_family, port], int(mode == 1))
                            if future:
                                future.result(timeout=20)
                        finally:
                            if filler:
                                filler.close()
                        assert output[0] == ('numeric' if mode == 0 else 'dns' if mode == 4 else 'hosts'), output
                        expected_result = 'RESULT exhausted' if scenario == 'exhausted' else 'RESULT success'
                        assert output[-1] == expected_result, (scenario, output)
                        expected_entries = 1 if mode == 0 or scenario == 'first-success' else 2
                        assert len(output) == expected_entries + 2, output
                        for index, line in enumerate(output[1:-1]):
                            timed = mode != 0 and index == 0
                            assert line.startswith(f'ENTRY {names[index]} ' + ('timed ' if timed else 'final ')), output
                            if scenario == 'first-success' or (index == 1 and scenario != 'exhausted'):
                                assert ' success ' in line, output
                            elif scenario == 'timeout-fallback' and index == 0:
                                assert line.endswith('timeout expiry'), output
                            else:
                                assert f' socket:{errno.ECONNREFUSED}:' in line, output
                            if not timed:
                                assert line.endswith(' none'), output
                        results[-1]['scenario'] = scenario
            for mode, label in [(2, 'source-error'), (3, 'invalid-host')]:
                assert execute(backend, command, audited, [mode, first_family, 0], 0) == [label, 'unresolved']
        print(backend, 'audited' if audited else 'production', 'PASS', flush=True)


def closure(path, seen):
    import re
    if path in seen:
        return
    seen.add(path)
    for name in re.findall(r'^import (\S+)', path.read_text(), re.M):
        if name != 'Base':
            closure((path.parent / name).resolve(), seen)
sources = set()
closure(ROOT / 'tests/http-connect-native.bend', sources)
sources.update([Path(__file__).resolve(), ROOT/'tests/channel_audit.py'])
sources.update(candidate / name for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend', 'effs/connect.c', 'effs/connect.js', 'effs/timer.c', 'effs/timer.js'])
sources.update(Path(f'{prefix}{suffix}') for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js'])
Path(f'{prefix}-result.json').write_text(json.dumps(dict(scope=__doc__, cases=results, sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)}), indent=2)+'\n')
