"""Native TLS socket IO against a local OpenSSL server; no production glue."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from tls13_handshake_check import server_context, encode

ROOT = Path(__file__).resolve().parents[1]


def serve(listener, context, mode):
    raw, _ = listener.accept()
    raw.settimeout(180)
    if mode == 'limit':
        with raw:
            assert raw.recv(1) == b'', 'rejected connection sent data or remained open'
        return
    stream = context.wrap_socket(raw, server_side=True)
    if mode == 'cancel':
        with stream:
            stream.sendall(b'R')
            assert stream.recv(1) == b'', 'cancelled connection remained open'
        return
    received = bytearray()
    while True:
        part = stream.recv(8192)
        if not part:
            break
        received.extend(part)
    assert received == bytes(range(256)) * 80, (len(received), received[:20])
    # TLS 1.3 close_notify closes only the peer's writer. Our reply remains legal.
    stream.sendall(b'ack')
    if mode == 'abrupt':
        os.close(stream.detach())
    else:
        stream.unwrap().close()


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='pi-tls-socket-') as temp, ThreadPoolExecutor(max_workers=1) as executor:
        context, _ = server_context(Path(temp), 'ecdsa')
        context.num_tickets = 2
        certificate = x509.load_pem_x509_certificate((Path(temp) / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
        for backend, command in [('native-1', [os.environ.get('TLS_SOCKET_NATIVE', 'build/tls-socket'), '--threads', '1']),
                                 ('native-4', [os.environ.get('TLS_SOCKET_NATIVE', 'build/tls-socket'), '--threads', '4']),
                                 ('bun', ['bun', os.environ.get('TLS_SOCKET_JS', 'build/tls-socket.js')])]:
            if len(sys.argv) > 1 and sys.argv[1] != backend:
                continue
            for mode in ['clean', 'abrupt', 'cancel', 'limit']:
                with socket.socket() as listener:
                    listener.bind(('127.0.0.1', 0))
                    listener.listen(1)
                    listener.settimeout(180)
                    server = executor.submit(serve, listener, context, mode)
                    run = subprocess.run(command + [str(listener.getsockname()[1]), encode(certificate), mode],
                                         cwd=ROOT, capture_output=True, text=True, timeout=240)
                    assert run.returncode == 0, (backend, mode, run.stdout[-2000:], run.stderr[-3000:])
                    assert run.stdout.strip() == 'PASS', run.stdout
                    server.result(timeout=10)
                print(f'{backend}: {mode} PASS', flush=True)
