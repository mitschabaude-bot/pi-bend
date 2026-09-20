"""Fresh injected/OS DNS IDs per exchange, with typed failure and abort cleanup.

Live random IDs may repeat. Checks assert request/reply matching and source
call counts, never sample uniqueness or cryptographic quality.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate', type=Path)
p.add_argument('--no-build', action='store_true')
a = p.parse_args()
candidate = a.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
if not a.no_build:
    for fixture in ['dns-lookup-ids', 'dns-lookup-random', 'dns-lookup-options']:
        for suffix in ['c', 'js']:
            subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '16',
                            '--stats', f'build/{fixture}-{suffix}-build.json', '--', str(bun),
                            str(candidate/'main.ts'), f'tests/{fixture}.bend', '-o',
                            f'build/{fixture}.{suffix}'], cwd=ROOT, check=True)
        subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                        f'build/{fixture}.c', '-lpthread', '-lm', '-o', f'build/{fixture}'],
                       cwd=ROOT, check=True)

def exact(peer, count):
    data = b''
    while len(data) < count:
        part = peer.recv(count-len(data))
        assert part, 'early EOF'
        data += part
    return data

def name(value):
    return bytes([len(value)]) + value + b'\0'

def question(value, kind):
    return name(value) + struct.pack('!HH', kind, 1)

def record(owner, kind, data):
    return name(owner) + struct.pack('!HHIH', kind, 1, 60, len(data)) + data

def cname(owner, target):
    return record(owner, 5, name(target))

def address(owner, kind):
    return record(owner, kind, bytes(range(1, 5 if kind == 1 else 17)))

def reply(identifier, owner, kind, answers):
    data = struct.pack('!6H', identifier, 0x8180, 1, len(answers), 0, 0) + question(owner, kind) + b''.join(answers)
    return struct.pack('!H', len(data)) + data

def selected(owner, kind):
    wire = ','.join(map(str, name(owner))) + ','
    return f'ok:{wire}:' + ('4,16909060,60;' if kind == 1 else '6,16909060,84281096,151653132,219025168,60;')

rows = []
for fixture in ['dns-lookup-ids', 'dns-lookup-random', 'dns-lookup-options']:
    injected = fixture != 'dns-lookup-random'
    extended = fixture == 'dns-lookup-options'
    opt = b''
    flags = 256
    if extended:
        flags = 288
        data = struct.pack('!HH',65001,2)+b'\0\xff'+struct.pack('!HH',65001,0)
        opt = b'\0'+struct.pack('!HHIH',41,1232,32768,len(data))+data
    modes = ['direct', 'aliases', 'pre', 'zero', 'type', 'deadline']
    if injected:
        modes += ['error-first', 'error-second', 'abort-source']
    for backend, command in [('native 1', [f'build/{fixture}', '--threads', '1']),
                             ('native 4', [f'build/{fixture}', '--threads', '4']),
                             ('Bun', [str(bun), f'build/{fixture}.js'])]:
        for number, family, host in [(4, socket.AF_INET, '127.0.0.1'), (6, socket.AF_INET6, '::1')]:
            for kind in [1, 28]:
                for mode in modes:
                    plan = {
                        'direct': [(b'a', [address(b'a', kind)])],
                        'aliases': [(b'a', [cname(b'a', b'b')]), (b'b', [cname(b'b', b'c')]), (b'c', [address(b'c', kind)])],
                        'error-second': [(b'a', [cname(b'a', b'b')])],
                        'deadline': [(b'a', [cname(b'a', b'b')]), (b'b', [])],
                    }.get(mode, [])
                    with socket.socket(family, socket.SOCK_STREAM) as listener, ThreadPoolExecutor(max_workers=1) as pool:
                        listener.bind((host, 0))
                        listener.listen(4)
                        listener.settimeout(4)
                        def serve():
                            for index, (owner, answers) in enumerate(plan):
                                with listener.accept()[0] as peer:
                                    peer.settimeout(4)
                                    size = struct.unpack('!H', exact(peer, 2))[0]
                                    query = exact(peer, size)
                                    identifier = struct.unpack('!H', query[:2])[0]
                                    assert query[2:] == struct.pack('!5H', flags, 1, 0, 0, bool(opt)) + question(owner, kind) + opt, query
                                    if injected:
                                        assert identifier == [0, 65535, 4660][index], (mode, index, identifier)
                                    if mode == 'deadline' and index == 0:
                                        time.sleep(.7)
                                    if mode == 'deadline' and index == 1:
                                        assert select.select([peer], [], [], .6)[0], 'deadline reset'
                                    else:
                                        # Unrelated replies must not cause another draw or finish the exchange.
                                        peer.sendall(reply(identifier ^ 1, owner, kind, answers) + reply(identifier, owner, kind, answers))
                                    assert peer.recv(1) == b'', 'exchange not closed'
                        future = pool.submit(serve) if plan else None
                        run = subprocess.run([*command, mode, str(number), str(listener.getsockname()[1]),
                                              str(15 if mode == 'type' else kind)], cwd=ROOT, capture_output=True,
                                             text=True, timeout=6)
                        if future:
                            future.result(timeout=5)
                        aborted_connections = 0
                        if mode == 'abort-source' and select.select([listener], [], [], 0)[0]:
                            # Parent-to-deadline forwarding is asynchronous. An
                            # in-flight connect/send may precede child delivery.
                            with listener.accept()[0] as peer:
                                peer.settimeout(2)
                                sent = b''
                                while True:
                                    chunk = peer.recv(4096)
                                    if not chunk:
                                        break
                                    sent += chunk
                                expected_query = struct.pack('!6H', 0, flags, 1, 0, 0, bool(opt)) + question(b'a', kind) + opt
                                expected_frame = struct.pack('!H', len(expected_query)) + expected_query
                                assert expected_frame.startswith(sent), sent
                            aborted_connections = 1
                        assert not select.select([listener], [], [], 0)[0], ('unexpected connection', fixture, backend, number, kind, mode, run)
                    outcome = {'direct': selected(b'a', kind), 'aliases': selected(b'c', kind),
                               'pre': 'connect:parent', 'abort-source': 'connect:parent', 'zero': 'zero',
                               'type': 'type', 'deadline': 'read:expiry',
                               'error-first': 'entropy:11:test source unavailable',
                               'error-second': 'entropy:38:test source unavailable'}[mode]
                    if mode == 'abort-source':
                        lines = run.stdout.splitlines()
                        assert lines and lines[0] in ['connect:parent', 'adopt:parent', 'read:parent'], (backend, run)
                        outcome = lines[0]
                    reason = 'parent' if mode in ['pre', 'abort-source'] else ('expiry' if mode == 'deadline' else 'none')
                    want = [outcome, reason]
                    draws = {'direct': 1, 'aliases': 3, 'pre': 0, 'zero': 0, 'type': 0,
                             'deadline': 2, 'error-first': 1, 'error-second': 2, 'abort-source': 1}[mode]
                    if injected:
                        want += [f'draws:{draws}', 'PASS DNS lookup IDs']
                    else:
                        want += ['PASS DNS address lookup']
                    assert run.returncode == 0 and not run.stderr and run.stdout.splitlines() == want, (fixture, backend, number, kind, mode, run, want)
                    rows.append(dict(extended=extended, source='injected' if injected else 'OS', backend=backend,
                                     family=number, query_type=kind, mode=mode, exchanges=len(plan),
                                     checked_draw_count=draws if injected else None,
                                     aborted_connections=aborted_connections, outcome=outcome))
        print(f'{fixture} {backend}: PASS', flush=True)
paths = ['packages/runtime/src/dns-query.bend','tests/dns-lookup-options.bend','build/dns-lookup-options','build/dns-lookup-options.js','packages/runtime/src/dns-address-lookup.bend', 'packages/runtime/src/dns-id.bend',
         'tests/dns-lookup-ids.bend', 'tests/dns-lookup-random.bend', 'tests/dns_lookup_ids_check.py',
         'build/dns-lookup-ids', 'build/dns-lookup-ids.js', 'build/dns-lookup-random', 'build/dns-lookup-random.js']
result = dict(scope=__doc__, candidate=str(candidate), compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']}, cases=rows, sha256={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in paths},
              builds={f'{fixture}-{suffix}':json.loads((ROOT/f'build/{fixture}-{suffix}-build.json').read_text())
                      for fixture in ['dns-lookup-ids', 'dns-lookup-random', 'dns-lookup-options'] for suffix in ['c', 'js']})
(ROOT/'build/dns-lookup-ids-result.json').write_text(json.dumps(result, indent=2)+'\n')
