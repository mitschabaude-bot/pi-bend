"""Read an authenticated TLS response while the upload is parked in socket IO.

A private test toolchain only shrinks socket buffers and reports IO park/shutdown
observations. It does not change the compiler, TLS, or production primitives.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading

from bend_toolchain import TOOLCHAIN
from tls_socket_check import ROOT, server_context, encode, x509, serialization


def replace(path, old, new):
    source = path.read_text()
    assert source.count(old) == 1, (path, old)
    path.write_text(source.replace(old, new))


def check(command, context, certificate, label, http=False):
    parked, aborted = threading.Event(), threading.Event()
    diagnostics = []
    with socket.socket() as listener, ThreadPoolExecutor(max_workers=2) as pool:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(180)

        def serve():
            raw, _ = listener.accept()
            raw.settimeout(180)
            with context.wrap_socket(raw, server_side=True) as stream:
                assert parked.wait(180), 'TLS uploader never parked'
                stream.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello' if http else b'R')
                # Keep the receive window closed until the client's read has
                # completed and triggered cancellation of the blocked writer.
                assert aborted.wait(180), 'early response did not unblock client'
                received = bytearray()
                try:
                    while part := stream.recv(8192):
                        received.extend(part)
                except (ssl.SSLError, ConnectionResetError):
                    # Cancellation may interrupt an encrypted record.
                    pass
                if http:
                    head, received = bytes(received).split(b'\r\n\r\n', 1)
                    assert head.startswith(b'POST / HTTP/1.1\r\n'), head
                    assert b'content-length: 65536' in head.lower(), head
                assert len(received) < 65536, 'whole upload completed'
                assert received == (bytes(range(256)) * 256)[:len(received)]

        server = pool.submit(serve)
        process = subprocess.Popen(command + [str(listener.getsockname()[1]), encode(certificate), '4' if http else 'backpressure'],
                                   cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def observe():
            for line in process.stderr:
                diagnostics.append(line.rstrip())
                if line.startswith('WRITE '):
                    parked.set()
                if line.startswith('SHUT '):
                    aborted.set()

        observer = pool.submit(observe)
        try:
            process.wait(timeout=240)
            output = process.stdout.read()
            observer.result(timeout=10)
            server.result(timeout=10)
            assert process.returncode == 0, (label, output, diagnostics)
            assert output.strip() == ('1;;unfinished;early' if http else 'PASS'), (label, output, diagnostics)
            assert parked.is_set() and aborted.is_set(), diagnostics
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    print(f'{label}: response during parked {"HTTPS" if http else "TLS"} upload; {"local stop without parent abort" if http else "cancellation reason"}; joined cleanup PASS', flush=True)


if __name__ == '__main__':
    http = '--http' in sys.argv[1:]
    source = 'tests/http-tls-exchange.bend' if http else 'tests/tls-socket.bend'
    with tempfile.TemporaryDirectory(prefix='tls-backpressure-', dir=ROOT / 'build') as temporary:
        directory = Path(temporary)
        compiler = directory / 'bend2'
        shutil.copytree(TOOLCHAIN, compiler)
        effects = compiler / 'effs'
        replace(effects / 'tcp_send_bytes.c', '  u64 cap = 64;',
                '  int small = 4096; setsockopt((int)w->hand, SOL_SOCKET, SO_SNDBUF, &small, sizeof(small));\n  u64 cap = 64;')
        replace(effects / 'tcp_send_bytes.c', '      return io_wait_on',
                '      fprintf(stderr, "WRITE %d\\n", fd); fflush(stderr);\n      return io_wait_on')
        replace(effects / 'tcp_send_bytes.js', '  const bytes = [];',
                '  const small = new Int32Array([4096]);\n  sys.setsockopt(fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1001 : 7, sys.ptr(small), 4);\n  const bytes = [];')
        replace(effects / 'tcp_send_bytes.js', '          io_park_on',
                '          process.stderr.write(`WRITE ${fd}\\n`);\n          io_park_on')
        replace(effects / 'tcp_shutdown.c', '  Term result =',
                '  fprintf(stderr, "SHUT %d\\n", fd); fflush(stderr);\n  Term result =')
        replace(effects / 'tcp_shutdown.js', '  return io_tup',
                '  process.stderr.write(`SHUT ${socket}\\n`);\n  return io_tup')
        compiler_command = str(compiler / 'main.ts')
        binary, javascript = directory / 'test', directory / 'test.js'
        subprocess.run(['sh', 'scripts/build-pure.sh', source, str(binary)],
                       cwd=ROOT, env=dict(os.environ, BEND=compiler_command), check=True)
        subprocess.run([compiler_command, source, '-o', str(javascript)], cwd=ROOT, check=True)
        context, _ = server_context(directory, 'ecdsa')
        context.num_tickets = 2
        certificate = x509.load_pem_x509_certificate((directory / 'certificate.pem').read_bytes()).public_bytes(serialization.Encoding.DER)
        for threads in ['1', '4']:
            check([str(binary), '--threads', threads], context, certificate, f'native-{threads}', http)
        check(['bun', str(javascript)], context, certificate, 'bun', http)
