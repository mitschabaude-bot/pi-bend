"""Native HTTP response framing and ownership over a real TLS socket."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile

from tls_socket_check import ROOT, server_context, encode, x509, serialization


def serve(listener, context, mode):
    raw, _ = listener.accept()
    raw.settimeout(180)
    with context.wrap_socket(raw, server_side=True) as stream:
        request = bytearray()
        while b'\r\n\r\n' not in request:
            request.extend(stream.recv(4096))
        head, body = bytes(request).split(b'\r\n\r\n', 1)
        assert head.startswith(b'POST / HTTP/1.1\r\n'), head
        assert b'content-length: 65536' in head.lower(), head
        if mode != 'early':
            while len(body) < 65536:
                part = stream.recv(8192)
                assert part, 'upload ended early'
                body += part
            assert body == bytes(range(256)) * 256
        if mode == 'chunked':
            reply = b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n'
        elif mode == 'truncated':
            reply = b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhe'
        else:
            reply = b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello'
        stream.sendall(reply)
        if mode == 'truncated':
            os.close(stream.detach())
            return
        # HTTP completion/early close must stop its transport without requiring
        # the server to finish consuming a request body or send close_notify.
        while stream.recv(8192):
            pass


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='pi-http-tls-') as temp, ThreadPoolExecutor(max_workers=1) as executor:
        context, _ = server_context(Path(temp), 'ecdsa')
        context.num_tickets = 2
        certificate = x509.load_pem_x509_certificate((Path(temp) / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
        for backend, command in [('native-1', ['build/http-tls-exchange', '--threads', '1']),
                                 ('native-4', ['build/http-tls-exchange', '--threads', '4']),
                                 ('bun', ['bun', 'build/http-tls-exchange.js'])]:
            if len(sys.argv) > 1 and sys.argv[1] != backend:
                continue
            for mode in ['fixed', 'chunked', 'early', 'truncated']:
                with socket.socket() as listener:
                    listener.bind(('127.0.0.1', 0))
                    listener.listen(1)
                    listener.settimeout(180)
                    server = executor.submit(serve, listener, context, mode)
                    run = subprocess.run(command + [str(listener.getsockname()[1]), encode(certificate), '4' if mode == 'early' else '0'],
                                         cwd=ROOT, capture_output=True, text=True, timeout=240)
                    assert run.returncode == 0, (backend, mode, run.stdout[-2000:], run.stderr[-3000:])
                    expected = {'early': '1;;unfinished;early', 'truncated': '1;104,101;unfinished;source-error'}.get(mode, '1;104,101,108,108,111;done;eof')
                    assert run.stdout.strip() == expected, (backend, mode, expected, run.stdout)
                    server.result(timeout=10)
                print(f'{backend}: HTTPS {mode}, shared parser, parent signal intact PASS', flush=True)
