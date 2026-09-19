"""Real loopback sockets and AbortSignal; run against the isolated candidate."""
import concurrent.futures
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = Path(sys.argv[1]).resolve()
launcher = ROOT / 'build/abortable-socket-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(CANDIDATE / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
environment = dict(os.environ, BEND=str(launcher))
binary = ROOT / 'build/abortable-socket'
subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/abortable-socket.bend', str(binary)], cwd=ROOT, env=environment, check=True)
javascript = binary.with_suffix('.js')
subprocess.run([str(launcher), 'tests/abortable-socket.bend', '-o', str(javascript)], cwd=ROOT, check=True)


def check(command, label):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            for index in range(24):
                with listener.accept()[0] as peer:
                    peer.settimeout(10)
                    mode = index % 6
                    if mode in [1, 4]:
                        peer.sendall(b'N')
                    elif mode == 5:
                        peer.shutdown(socket.SHUT_WR)
                    # Aborted sends must be rejected before any byte is sent.
                    assert peer.recv(1) == b'', (label, index, 'unexpected client data')

        future = pool.submit(server)
        result = subprocess.run([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, capture_output=True, timeout=15)
        future.result(timeout=3)
        assert result.returncode == 0, (label, result.stdout, result.stderr)
        assert result.stdout == 'PASS abortable socket\n', result.stdout
        assert not result.stderr, result.stderr
    print(label + ': 24 abort/read/send/close lifecycles PASS', flush=True)


for threads in ['1', '4']:
    check([str(binary), '--threads', threads], 'native ' + threads)
check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun')
