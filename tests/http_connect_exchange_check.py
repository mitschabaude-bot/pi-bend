"""Local numeric HTTP connection, AbortSignal handoff and cleanup checks.

Production programs only; this does not audit every scheduler interleaving.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import select
import shlex
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path,nargs='?',default=TOOLCHAIN)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
candidate = args.candidate.resolve()
bun = Path.home() / '.bun/bin/bun'
(ROOT / 'build').mkdir(exist_ok=True)
launcher = ROOT / 'build/http-connect-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(bun)) + ' ' + shlex.quote(str(candidate / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
if not args.no_build:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '24', '--stats', 'build/http-connect-build.json', '--', 'sh', 'scripts/build-pure.sh', 'tests/http-connect-exchange.bend', 'build/http-connect-exchange'], cwd=ROOT, env=dict(os.environ, BEND=str(launcher)), check=True)
subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '8', '--stats', 'build/http-connect-js-build.json', '--', str(launcher), 'tests/http-connect-exchange.bend', '-o', 'build/http-connect-exchange.js'], cwd=ROOT, check=True)
results = []

def run(label, command, mode, family, port, code=0):
    result = subprocess.run([*command, mode, str(family), str(port), str(code)], cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0 and result.stdout == 'PASS HTTP connect exchange\n' and not result.stderr, (label, mode, result)
    results.append(dict(backend=label, mode=mode, family=family, expected_errno=code))

for label, command in [('native 1', ['build/http-connect-exchange', '--threads', '1']), ('native 4', ['build/http-connect-exchange', '--threads', '4']), ('Bun', [str(bun), 'build/http-connect-exchange.js'])]:
    for family, host, number in [(socket.AF_INET, '127.0.0.1', 4), (socket.AF_INET6, '::1', 6)]:
        for mode in ['success', 'read']:
            with socket.socket(family, socket.SOCK_STREAM) as listener, ThreadPoolExecutor(max_workers=1) as pool:
                listener.bind((host, 0)); listener.listen(8); listener.settimeout(15)
                def serve():
                    with listener.accept()[0] as peer:
                        peer.settimeout(15)
                        wire = b''
                        while b'\r\n\r\n' not in wire:
                            data = peer.recv(1024); assert data; wire += data
                            assert len(wire) < 16384
                        head, body = wire.split(b'\r\n\r\n', 1)
                        first, *lines = head.split(b'\r\n')
                        fields = dict(line.split(b': ', 1) for line in lines)
                        assert first == b'POST /connect HTTP/1.1', first
                        assert fields[b'host'] == b'logical.example', fields
                        assert fields[b'content-length'] == b'5', fields
                        while len(body) < 5:
                            data = peer.recv(1024); assert data; body += data
                        assert body == b'hello', body
                        peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n' + (b'OK' if mode == 'success' else b''))
                        assert peer.recv(1) == b'', 'socket did not close'
                future = pool.submit(serve)
                run(label, command, mode, number, listener.getsockname()[1])
                future.result(timeout=20)
        with socket.socket(family, socket.SOCK_STREAM) as reserved:
            reserved.bind((host, 0))
            run(label, command, 'error', number, reserved.getsockname()[1], errno.ECONNREFUSED)
            run(label, command, 'error', number, 65536, errno.EINVAL)
        with socket.socket(family, socket.SOCK_STREAM) as listener:
            listener.bind((host, 0)); listener.listen(8)
            for mode in ['pre', 'zero']:
                run(label, command, mode, number, listener.getsockname()[1])
                assert not select.select([listener], [], [], .05)[0], 'guard opened a connection'
        with socket.socket(family, socket.SOCK_STREAM) as listener, socket.socket(family, socket.SOCK_STREAM) as filler, socket.socket(family, socket.SOCK_STREAM) as probe:
            listener.bind((host, 0)); listener.listen(0)
            filler.settimeout(2); filler.connect(listener.getsockname())
            probe.setblocking(False)
            assert probe.connect_ex(listener.getsockname()) == errno.EINPROGRESS
            assert not select.select([], [probe], [], .05)[1]
            probe.close()
            run(label, command, 'pending', number, listener.getsockname()[1])
    print(label + ': HTTP connection and abort handoff PASS', flush=True)
paths = [ROOT / 'packages/runtime/src/http-exchange.bend', ROOT / 'tests/http-connect-exchange.bend', ROOT / 'tests/http_connect_exchange_check.py', ROOT / 'packages/runtime/src/http-message.bend', ROOT / 'tests/http-request-exchange.bend', candidate / 'comp.ts', candidate / 'base.bend', ROOT / 'build/http-connect-exchange', ROOT / 'build/http-connect-exchange.js']
report = dict(scope=__doc__, cases=results, sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
(ROOT / 'build/http-connect-result.json').write_text(json.dumps(report, indent=2) + '\n')
