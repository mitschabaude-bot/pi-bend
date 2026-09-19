"""Contract checks for the isolated, uninstalled raw TCP primitive candidate."""
import concurrent.futures
import os
from pathlib import Path
import socket
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(Path.home() / '.bend/bin/bend'))
output = ROOT / 'build/tcp-bytes-contract'
source = 'tests/tcp-bytes-contract.bend'
subprocess.run(['sh', 'scripts/build-pure.sh', source, str(output)], cwd=ROOT, check=True)
subprocess.run([BEND, source, '-o', str(output.with_suffix('.js'))], cwd=ROOT, check=True)
error_output = ROOT / 'build/tcp-bytes-errors'
subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/tcp-bytes-errors.bend', str(error_output)], cwd=ROOT, check=True)
subprocess.run([BEND, 'tests/tcp-bytes-errors.bend', '-o', str(error_output.with_suffix('.js'))], cwd=ROOT, check=True)
sent = bytes(range(256))
received = sent * 3 + bytes([239, 187, 191, 237, 160, 128, 255, 0])


def check(command, label):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            with listener.accept()[0] as client:
                client.settimeout(10)
                data = b''
                while len(data) < len(sent):
                    part = client.recv(19)
                    if not part:
                        break
                    data += part
                # Invalid/empty sends must not have written any prefix.
                assert data == sent, data
                for start in range(0, len(received), 11):
                    client.sendall(received[start:start + 11])
                client.shutdown(socket.SHUT_WR)
                assert client.recv(1) == b'', 'unexpected extra bytes before client close'

        future = pool.submit(server)
        lines = subprocess.check_output(
            [*command, 'p' + str(listener.getsockname()[1])], text=True, timeout=15).splitlines()
        assert lines[-1] == 'EOF', lines[-1:]
        chunks = [bytes(map(int, line.split(','))) for line in lines[:-1]]
        assert all(0 < len(chunk) <= 7 for chunk in chunks)
        assert b''.join(chunks) == received
        future.result()
        print(f'PASS raw TCP {label}: invalid/empty sends, zero read, partial reads, repeated EOF, socket reuse', flush=True)


def check_errors(command, label):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            with listener.accept()[0] as client:
                client.settimeout(10)
                client.sendall(b'R')
                assert client.recv(1) == b'A'
                # Reset only after the client has acknowledged readiness.
                client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))

        future = pool.submit(server)
        actual = subprocess.check_output(
            [*command, 'p' + str(listener.getsockname()[1])], text=True, timeout=15)
        assert actual == 'ERRORS\n', actual
        future.result()
        print(f'PASS raw TCP {label}: reset read and subsequent send return typed errors; socket closes', flush=True)


for threads in ['1', '4']:
    check([str(output), '--threads', threads], 'native threads ' + threads)
    check_errors([str(error_output), '--threads', threads], 'native threads ' + threads)
check([str(Path.home() / '.bun/bin/bun'), str(output.with_suffix('.js'))], 'JS backend')
check_errors([str(Path.home() / '.bun/bin/bun'), str(error_output.with_suffix('.js'))], 'JS backend')
