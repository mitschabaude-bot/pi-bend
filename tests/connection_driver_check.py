"""Finite connection-driver traces and ownership, plus real dual-family fallback.

Injected callbacks validate traversal and retained reports. Loopback checks use
native timed/final connectors. Resource instrumentation is test-only.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import socket
import subprocess
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
candidate = args.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
prefix = ROOT / 'build/connection-driver'

def replace_once(source, before, after):
    assert source.count(before) == 1, before
    return source.replace(before, after)

if not args.no_build:
    for suffix in ['c', 'js']:
        with Path(f'{prefix}-{suffix}.log').open('w') as log:
            subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'{prefix}-{suffix}-build.json', '--', str(bun), str(candidate / 'main.ts'), 'tests/connection-driver.bend', '-o', f'{prefix}.{suffix}'], cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)

c = Path(f'{prefix}.c').read_text()
original = (candidate / 'effs/timer.c').read_text()
changed = 'static unsigned probe_created,probe_live,probe_peak;\n' + original
changed = replace_once(changed, '  row->gen += 1;', '  probe_created++; probe_live++; if(probe_live>probe_peak)probe_peak=probe_live;\n  row->gen += 1;')
changed = replace_once(changed, '  row->live = 0;', '  probe_live--;\n  row->live = 0;')
audit = r'''
static void __attribute__((destructor)) attempt_audit(void) {
 unsigned timers=0,waiters=0,channels=0,connects=0,fds=0,sockets=0;
 for(u32 i=0;i<timer_len;i++){timers+=timer_rows[i].live;waiters+=timer_rows[i].waiter!=NULL;}
 for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
 for(u32 i=0;i<connect_len;i++){connects+=connect_rows[i].live;fds+=connect_rows[i].fd>=0;waiters+=connect_rows[i].waiter!=NULL;}
 for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
 fprintf(stderr,"RESOURCES %u %u %u %u %u %u %u %u %u %u\n",probe_created,probe_peak,probe_live,timers,waiters,channels,connects,fds,sockets,io_park.head!=NULL);
}
'''
Path(f'{prefix}-audit.c').write_text(replace_once(c, original, changed) + audit)
for suffix in ['', '-audit']:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c', '-lpthread', '-lm', '-o', f'{prefix}{suffix}'], check=True)
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

def execute(backend, command, audited, arguments, expected_timers):
    result = subprocess.run([*command, *map(str, arguments)], cwd=ROOT, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (backend, arguments, result)
    values = None
    if audited:
        lines = result.stderr.strip().splitlines()
        values = list(map(int, next(x for x in lines if x.startswith('RESOURCES ')).split()[1:]))
        assert values[0] == expected_timers and values[1] == min(1, expected_timers) and not any(values[2:]), (backend, arguments, values)
        if backend == 'Bun':
            assert 'AUDIT 0 0 0' in lines and len(lines) == 2, result.stderr
        else:
            assert len(lines) == 1, result.stderr
    else:
        assert not result.stderr, result.stderr
    results.append(dict(backend=backend, audited=audited, arguments=arguments, resources=values))
    return result.stdout.strip().splitlines()


def expected(scenario, target, count):
    calls, entries = [], []
    if scenario == 7:
        return ['RESULT abort:stop']
    final = 'empty' if count == 0 else 'exhausted'
    released = False
    for index in range(1, count + 1):
        mode = 'final' if index == count else 'timed'
        calls.append(f'CALL {index} {mode}')
        outcome = f'socket:{index}:original'
        stop = False
        if index == target:
            if scenario == 1:
                outcome, final, stop = 'success', 'success', True
            elif scenario == 2:
                outcome = 'timeout'
            elif scenario == 3:
                outcome, final, stop = 'abort:reported', 'abort:reported', True
            elif scenario == 4:
                outcome, final, stop = 'unexpected', 'unexpected', True
            elif scenario == 5:
                final, stop = 'abort:stop', True
            elif scenario in [6, 8]:
                outcome, final, stop, released = 'success', 'abort:' + ('stop' if scenario == 6 else 'default'), True, True
        entries.append(f'ENTRY {index} {mode} {outcome} expiry')
        if stop:
            break
    return calls + (['RELEASE'] if released else []) + entries + ['RESULT ' + final]

for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [('native 1', [f'{prefix}{suffix}', '--threads', '1']), ('native 4', [f'{prefix}{suffix}', '--threads', '4']), ('Bun', [str(bun), f'{prefix}{suffix}.js'])]:
        for count in range(7):
            for target in range(1, count + 2):
                for scenario in range(9):
                    actual = execute(backend, command, audited, [scenario, target, count], 0)
                    assert actual == expected(scenario, target, count), (backend, audited, scenario, target, count, actual)
        for first_family in [4, 6]:
            first_af, first_host = (socket.AF_INET, '127.0.0.1') if first_family == 4 else (socket.AF_INET6, '::1')
            second_af, second_host = (socket.AF_INET6, '::1') if first_family == 4 else (socket.AF_INET, '127.0.0.1')
            names = ['2130706433', 'ipv6'] if first_family == 4 else ['ipv6', '2130706433']
            for scenario in ['first-success', 'refused-fallback', 'timeout-fallback', 'exhausted']:
                with socket.socket(first_af, socket.SOCK_STREAM) as first, socket.socket(second_af, socket.SOCK_STREAM) as second, ThreadPoolExecutor(max_workers=1) as pool:
                    if first_af == socket.AF_INET6:
                        first.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                    else:
                        second.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
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
                        output = execute(backend, command, audited, [10, first_family, port], 1)
                        if future:
                            future.result(timeout=20)
                    finally:
                        if filler:
                            filler.close()
                    expected_result = 'RESULT exhausted' if scenario == 'exhausted' else 'RESULT success'
                    assert output[-1] == expected_result, (scenario, output)
                    assert len(output) == (2 if scenario == 'first-success' else 3), (scenario, output)
                    for index, line in enumerate(output[:-1]):
                        assert line.startswith(f'ENTRY {names[index]} ' + ('timed ' if index == 0 else 'final ')), output
                        if scenario == 'first-success' or (index == 1 and scenario != 'exhausted'):
                            assert ' success ' in line, output
                        elif scenario == 'timeout-fallback' and index == 0:
                            assert line.endswith('timeout expiry'), output
                        else:
                            assert f' socket:{errno.ECONNREFUSED}:' in line, output
                        if index == 1:
                            assert line.endswith(' none'), output
                    results[-1]['native_scenario'] = scenario
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
closure(ROOT / 'tests/connection-driver.bend', sources)
sources.update([Path(__file__).resolve(), ROOT/'tests/channel_audit.py'])
sources.update(candidate / name for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend', 'effs/connect.c', 'effs/connect.js', 'effs/timer.c', 'effs/timer.js'])
sources.update(Path(f'{prefix}{suffix}') for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js'])
Path(f'{prefix}-result.json').write_text(json.dumps(dict(scope=__doc__, cases=results, sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)}), indent=2)+'\n')
