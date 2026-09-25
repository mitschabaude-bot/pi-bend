"""Finite loopback checks of timed/final connection attempts and resource retirement.

Unmodified and audited programs run on native one/four threads and Bun. Injected
settlement covers late deadline diagnostics; it is not a scheduler race proof.
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
prefix = ROOT / 'build/connection-attempt'

def replace_once(source, before, after):
    assert source.count(before) == 1, before
    return source.replace(before, after)

if not args.no_build:
    for suffix in ['c', 'js']:
        with Path(f'{prefix}-{suffix}.log').open('w') as log:
            subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', f'{prefix}-{suffix}-build.json', '--', str(bun), str(candidate / 'main.ts'), 'tests/connection-attempt.bend', '-o', f'{prefix}.{suffix}'], cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)

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

def run(backend, command, audited, timed, mode, family, port, code=0):
    result = subprocess.run([*command, str(int(timed)), str(mode), str(family), str(port), str(code)], cwd=ROOT, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0 and result.stdout == 'PASS connection attempt\n', (backend, audited, timed, mode, result)
    values = None
    if audited:
        lines = result.stderr.strip().splitlines()
        resources = next(x for x in lines if x.startswith('RESOURCES '))
        values = list(map(int, resources.split()[1:]))
        expected = 0 if not timed or mode in [2, 3] else 1 if mode in [5, 6, 7] else 16
        assert values[0] == expected and values[1] == min(1, expected) and not any(values[2:]), (backend, timed, mode, values)
        if backend == 'Bun':
            assert 'AUDIT 0 0 0' in lines and len(lines) == 2, result.stderr
        else:
            assert len(lines) == 1, result.stderr
    else:
        assert not result.stderr, result.stderr
    results.append(dict(backend=backend, audited=audited, timed=timed, mode=mode, family=family, error=code, resources=values))

for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [('native 1', [f'{prefix}{suffix}', '--threads', '1']), ('native 4', [f'{prefix}{suffix}', '--threads', '4']), ('Bun', [str(bun), f'{prefix}{suffix}.js'])]:
        for timed in [False, True]:
            for af, host, family in [(socket.AF_INET, '127.0.0.1', 4), (socket.AF_INET6, '::1', 6)]:
                with socket.socket(af, socket.SOCK_STREAM) as listener, ThreadPoolExecutor(max_workers=1) as pool:
                    listener.bind((host, 0)); listener.listen(16); listener.settimeout(15)
                    def serve():
                        for _ in range(16):
                            with listener.accept()[0] as peer:
                                peer.settimeout(10)
                                assert peer.recv(1) == b''
                    future = pool.submit(serve)
                    run(backend, command, audited, timed, 0, family, listener.getsockname()[1])
                    future.result(timeout=20)
                with socket.socket(af, socket.SOCK_STREAM) as closed:
                    closed.bind((host, 0)); port = closed.getsockname()[1]
                    run(backend, command, audited, timed, 1, family, port, errno.ECONNREFUSED)
                    run(backend, command, audited, timed, 1, family, 65536, errno.EINVAL)
                    run(backend, command, audited, timed, 2, family, port)
                    run(backend, command, audited, timed, 3, family, port)
                for mode in ([4, 5] if timed else [5]):
                    with socket.socket(af, socket.SOCK_STREAM) as listener, socket.socket(af, socket.SOCK_STREAM) as filler, socket.socket(af, socket.SOCK_STREAM) as probe:
                        listener.bind((host, 0)); listener.listen(0)
                        filler.settimeout(2); filler.connect(listener.getsockname())
                        probe.setblocking(False)
                        assert probe.connect_ex(listener.getsockname()) == errno.EINPROGRESS
                        assert not select.select([], [probe], [], .05)[1]
                        probe.close()
                        run(backend, command, audited, timed, mode, family, listener.getsockname()[1])
        for mode in [6, 7]:
            run(backend, command, audited, True, mode, 4, 0)
        print(backend, 'audited' if audited else 'production', 'PASS', flush=True)

# Capture the runtime import closure, compiler, and emitted artifacts for replay.
def closure(path, seen):
    import re
    if path in seen:
        return
    seen.add(path)
    for name in re.findall(r'^import (\S+)', path.read_text(), re.M):
        if name != 'Base':
            closure((path.parent / name).resolve(), seen)
sources = set()
closure(ROOT / 'tests/connection-attempt.bend', sources)
sources.update([Path(__file__).resolve(), ROOT/'tests/channel_audit.py'])
sources.update(candidate / name for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend', 'effs/connect.c', 'effs/connect.js', 'effs/timer.c', 'effs/timer.js'])
sources.update(Path(f'{prefix}{suffix}') for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js'])
report = dict(scope=__doc__, cases=results, sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)})
Path(f'{prefix}-result.json').write_text(json.dumps(report, indent=2)+'\n')
