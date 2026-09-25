"""Dedicated socket leases through HTTP decoding, with real cancellation/EOF."""
import concurrent.futures
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
launcher = ROOT / 'build/http-socket-source-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(CANDIDATE / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
environment = dict(os.environ, BEND=str(launcher))
binary = ROOT / 'build/http-socket-source'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'tests/http-socket-source.bend', str(binary)], cwd=ROOT, env=environment, check=True)
javascript = binary.with_suffix('.js')
subprocess.run([str(launcher), 'tests/http-socket-source.bend', '-o', str(javascript)], cwd=ROOT, check=True)


def check(command, label):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            for index in range(21):
                with listener.accept()[0] as peer:
                    peer.settimeout(10)
                    mode = index % 7
                    head = b'HTTP/1.1 200 OK\r\n'
                    if mode == 0:
                        peer.sendall(head + b'Content-Length: 3\r\n\r\nabc')
                    elif mode == 1:
                        peer.sendall(head + b'Transfer-Encoding: chunked\r\n\r\n1\r\na\r\n2\r\nbc\r\n0\r\nX-Trail: yes\r\n\r\n')
                    elif mode == 2:
                        peer.sendall(head + b'\r\nabc')
                        peer.shutdown(socket.SHUT_WR)
                    elif mode == 3:
                        # Never send EOF: only client abort can finish this body.
                        peer.sendall(head + b'\r\n')
                    elif mode == 4:
                        peer.sendall(head + b'Content-Length: 3\r\n\r\n')
                    elif mode == 5:
                        peer.sendall(head + b'Content-Length: 3\r\n\r\na')
                        peer.shutdown(socket.SHUT_WR)
                    assert peer.recv(1) == b'', (label, index, 'unexpected client data')

        future = pool.submit(server)
        result = subprocess.run([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, capture_output=True, timeout=15)
        future.result(timeout=3)
        assert result.returncode == 0, (label, result.stdout, result.stderr)
        lines = result.stdout.splitlines()
        assert len(lines) == 21, lines
        for index, line in enumerate(lines):
            mode = index % 7
            if mode in [0, 1, 2]:
                assert line == '1;97,98,99;done;eof', (index, line)
            elif mode == 3:
                assert line in ['0;;unfinished;abort:stop', '1;;unfinished;abort:stop'], (index, line)
            elif mode == 4:
                assert line == '1;;unfinished;early', (index, line)
            elif mode == 5:
                assert line == '1;97;unfinished;decode', (index, line)
            else:
                assert line == 'invalid-size', (index, line)
        assert not result.stderr, result.stderr
    print(label + ': 21 real socket → HTTP response lifecycle traces PASS', flush=True)



for threads in ['1', '4']:
    check([str(binary), '--threads', threads], 'native ' + threads)
check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun')
