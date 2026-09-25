"""Basic loopback smoke test for the uninstalled raw-TCP primitive candidate.

Set BEND to an isolated compiler with patches/experimental/bend-tcp-bytes.patch.
This does not cover partial I/O, EOF, errors, backpressure or performance.
"""
import concurrent.futures
import os
from pathlib import Path
from bend_toolchain import BEND
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BEND = BEND
output = ROOT / 'build/tcp-bytes-probe'
source = 'tests/tcp-bytes-probe.bend'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', source, str(output)], cwd=ROOT, check=True)
subprocess.run([BEND, source, '-o', str(output.with_suffix('.js'))], cwd=ROOT, check=True)
payload = bytes(range(256))


def check(command):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            with listener.accept()[0] as client:
                client.settimeout(10)
                data = b''
                while len(data) < len(payload):
                    chunk = client.recv(256)
                    if not chunk:
                        break
                    data += chunk
                assert data == payload, (len(data), data)
                client.sendall(payload)

        future = pool.submit(server)
        actual = subprocess.check_output(
            [*command, 'p' + str(listener.getsockname()[1])], text=True, timeout=10).strip()
        got = bytes(map(int, actual.split(',')))
        # A single short read is legal; this probe checks its exact byte prefix.
        # Comprehensive tests must accumulate reads through EOF separately.
        assert got and payload.startswith(got), got
        future.result()
        return len(got)


for threads in ['1', '4']:
    count = check([str(output), '--threads', threads])
    print(f'PASS raw TCP candidate smoke: sent 256 bytes, received {count}; native threads {threads}')
count = check([str(Path.home() / '.bun/bin/bun'), str(output.with_suffix('.js'))])
print(f'PASS raw TCP candidate smoke: sent 256 bytes, received {count}; JS backend')
