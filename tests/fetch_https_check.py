"""Public native fetch: hosts routing, URL authority, TLS authorization and body ownership."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import socket
import os
import ssl
import subprocess
import sys
import tempfile

from tls_socket_check import ROOT, server_context, encode, x509, serialization


def serve(listener, context, mode):
    if mode == 'disabled':
        try:
            peer, _ = listener.accept()
        except TimeoutError:
            return
        peer.close()
        raise AssertionError('disabled TLS dialed a socket')
    raw, _ = listener.accept()
    raw.settimeout(180)
    if mode == 'denied':
        try:
            stream = context.wrap_socket(raw, server_side=True)
        except (ssl.SSLError, ConnectionResetError):
            return
        stream.close()
        raise AssertionError('rejected certificate completed a handshake')
    stream = raw if mode == 'plain' else context.wrap_socket(raw, server_side=True)
    with stream:
        request = bytearray()
        while b'\r\n\r\n' not in request:
            part = stream.recv(4096)
            assert part, 'request ended early'
            request.extend(part)
        hostname = '127.0.0.1' if mode == 'numeric' else 'tls.test'
        expected = f'GET /? HTTP/1.1\r\nhost: {hostname}:{listener.getsockname()[1]}\r\n\r\n'.encode()
        assert request == expected, request
        stream.sendall(b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n')
        assert stream.recv(1) == b'', 'response completion did not close transport'


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='pi-fetch-https-') as temporary, ThreadPoolExecutor(max_workers=1) as executor:
        directory = Path(temporary)
        context, _ = server_context(directory, 'ecdsa')
        context.num_tickets = 2
        names = []
        context.set_servername_callback(lambda socket, name, context: names.append(name))
        certificate = x509.load_pem_x509_certificate((directory / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
        resolver, hosts = directory / 'resolv.conf', directory / 'hosts'
        resolver.write_text('nameserver 127.0.0.1\n')
        hosts.write_text('127.0.0.1 tls.test\n')
        for backend, command in [('native-1', [os.environ.get('FETCH_HTTPS_NATIVE', 'build/fetch-https'), '--threads', '1']),
                                 ('native-4', [os.environ.get('FETCH_HTTPS_NATIVE', 'build/fetch-https'), '--threads', '4']),
                                 ('bun', ['bun', os.environ.get('FETCH_HTTPS_JS', 'build/fetch-https.js')])]:
            if len(sys.argv) > 1 and sys.argv[1] != backend:
                continue
            for mode in ['domain', 'numeric', 'plain', 'disabled', 'denied', 'unreachable']:
                names.clear()
                with socket.socket() as listener:
                    listener.bind(('127.0.0.1', 0))
                    if mode != 'unreachable':
                        listener.listen(1)
                    listener.settimeout(2 if mode == 'disabled' else 180)
                    server = None if mode in ['disabled', 'unreachable'] else executor.submit(serve, listener, context, mode)
                    run = subprocess.run(command + [str(listener.getsockname()[1]), encode(certificate), str(resolver), str(hosts), mode],
                                         cwd=ROOT, capture_output=True, text=True, timeout=240)
                    assert run.returncode == 0, (backend, mode, run.stdout[-2000:], run.stderr[-3000:])
                    assert run.stdout.strip() == 'PASS', run.stdout
                    if mode == 'disabled':
                        serve(listener, context, mode)
                    elif server is not None:
                        server.result(timeout=10)
                expected_names = [] if mode in ['plain', 'disabled', 'unreachable'] else [None if mode == 'numeric' else 'tls.test']
                assert names == expected_names, (backend, mode, names)
                print(f'{backend}: fetch {mode}, authority/target/SNI and authorizer binding PASS', flush=True)
