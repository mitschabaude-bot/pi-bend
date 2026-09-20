"""Two address lookups share one caller-owned deadline and entropy source.

Loopback TCP replies exercise success, expiry between/during calls, pre-abort,
validation and source failure on native one/four threads and Bun.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
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
bun = Path.home()/'.bun/bin/bun'
if not a.no_build:
    for suffix in ['c', 'js']:
        subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '16',
                        '--stats', f'build/dns-lookup-shared-{suffix}-build.json', '--',
                        str(bun), str(candidate/'main.ts'), 'tests/dns-lookup-shared.bend',
                        '-o', f'build/dns-lookup-shared.{suffix}'], cwd=ROOT, check=True)
subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                'build/dns-lookup-shared.c', '-lpthread', '-lm', '-o',
                'build/dns-lookup-shared'], cwd=ROOT, check=True)

def exact(peer, size):
    data = b''
    while len(data) < size:
        part = peer.recv(size-len(data))
        assert part, 'early EOF'
        data += part
    return data

def name(owner):
    return bytes([len(owner)]) + owner + b'\0'

def answer(identifier, owner, kind):
    wire = name(owner)
    value = bytes(range(1, 5 if kind == 1 else 17))
    data = (struct.pack('!6H', identifier, 0x8180, 1, 1, 0, 0) + wire +
            struct.pack('!HH', kind, 1) + wire + struct.pack('!HHIH', kind, 1, 60, len(value)) + value)
    return struct.pack('!H', len(data)) + data

def selected(owner, kind):
    wire = ''.join(str(x)+',' for x in name(owner))
    return 'ok:' + wire + ':' + ('4,16909060,60;' if kind == 1 else '6,16909060,84281096,151653132,219025168,60;')

rows = []
for backend, command in [('native 1', ['build/dns-lookup-shared', '--threads', '1']),
                         ('native 4', ['build/dns-lookup-shared', '--threads', '4']),
                         ('Bun', [str(bun), 'build/dns-lookup-shared.js'])]:
    for family, host in [(socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')]:
        number = 4 if family == socket.AF_INET else 6
        for kind in [1, 28]:
            for mode in ['direct', 'expiry-before', 'expiry-during', 'pre', 'zero', 'type', 'error-first', 'error-second']:
                owners = {'direct': [b'a', b'b'], 'expiry-before': [b'a'],
                          'expiry-during': [b'a', b'b'], 'error-second': [b'a']}.get(mode, [])
                with socket.socket(family, socket.SOCK_STREAM) as listener, ThreadPoolExecutor(max_workers=1) as pool:
                    listener.bind((host, 0)); listener.listen(4); listener.settimeout(4)
                    def serve():
                        for index, owner in enumerate(owners):
                            with listener.accept()[0] as peer:
                                peer.settimeout(4)
                                query = exact(peer, struct.unpack('!H', exact(peer, 2))[0])
                                identifier = [0, 65535][index]
                                assert query == struct.pack('!6H', identifier, 256, 1, 0, 0, 0) + name(owner) + struct.pack('!HH', kind, 1), query
                                if mode == 'expiry-during' and index == 0:
                                    time.sleep(.7)
                                if mode == 'expiry-during' and index == 1:
                                    assert select.select([peer], [], [], .6)[0], 'second lookup reset deadline'
                                else:
                                    peer.sendall(answer(identifier, owner, kind))
                                assert peer.recv(1) == b'', 'lookup left exchange open'
                    future = pool.submit(serve) if owners else None
                    result = subprocess.run([*command, mode, str(number), str(listener.getsockname()[1]),
                                             str(15 if mode == 'type' else kind)], cwd=ROOT,
                                            capture_output=True, text=True, timeout=6)
                    if future: future.result(timeout=5)
                    assert not select.select([listener], [], [], 0)[0], ('unexpected exchange', result)
                first, second, reason, draws = {
                    'direct': (selected(b'a', kind), selected(b'b', kind), 'none', 2),
                    'expiry-before': (selected(b'a', kind), 'connect:expiry', 'expiry', 1),
                    'expiry-during': (selected(b'a', kind), 'read:expiry', 'expiry', 2),
                    'pre': ('connect:parent', 'connect:parent', 'parent', 0),
                    'zero': ('zero', 'zero', 'none', 0),
                    'type': ('type', 'type', 'none', 0),
                    'error-first': ('entropy:11:test source unavailable', 'entropy:11:test source unavailable', 'none', 2),
                    'error-second': (selected(b'a', kind), 'entropy:38:test source unavailable', 'none', 2),
                }[mode]
                expected = [first, 'none', second, 'none', reason, 'draws:'+str(draws)]
                assert result.returncode == 0 and not result.stderr and result.stdout.splitlines() == expected, (backend, number, kind, mode, result, expected)
                rows.append(dict(backend=backend, family=number, kind=kind, mode=mode, exchanges=len(owners), draws=draws, output=expected))
    print(backend + ': shared deadline PASS', flush=True)
paths = ['packages/runtime/src/dns-address-lookup.bend', 'tests/dns-lookup-shared.bend',
         'tests/dns_lookup_shared_check.py', 'tests/dns-lookup-ids.bend',
         'build/dns-lookup-shared', 'build/dns-lookup-shared.js']
record = dict(scope=__doc__, cases=rows,
              sha256={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in paths},
              builds={suffix:json.loads((ROOT/f'build/dns-lookup-shared-{suffix}-build.json').read_text()) for suffix in ['c','js']},
              compiler_sha256={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/dns-lookup-shared-result.json').write_text(json.dumps(record, indent=2)+'\n')
