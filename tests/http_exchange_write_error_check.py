"""Inject a body-write EPIPE in a disposable compiler; verify owned cleanup."""
import concurrent.futures
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()


def replace(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, (path, old)
    path.write_text(text.replace(old, new))


def check(command, label):
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            with listener.accept()[0] as peer:
                peer.settimeout(10)
                request = b''
                while chunk := peer.recv(1024):
                    request += chunk
                assert request == b'POST / HTTP/1.1\r\ncontent-length: 3\r\ncontent-type: text/plain;charset=UTF-8\r\nhost: example.test\r\n\r\n', request

        future = pool.submit(server)
        result = subprocess.run([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, capture_output=True, timeout=15)
        future.result(timeout=3)
        assert result.returncode == 0, (label, result.stdout, result.stderr)
        assert result.stdout == 'PASS exchange write failure\n', result.stdout
        rows = [line.split() for line in result.stderr.splitlines()]
        duplicate = [r for r in rows if r[0] == 'DUP']
        assert len(duplicate) == 2, rows
        assert sorted(r[1] for r in rows if r[0] == 'CLOSE') == sorted([duplicate[0][1], duplicate[0][2], duplicate[1][2]]), rows
        assert duplicate[0][1] == duplicate[1][1], rows
        assert len(rows) == 5, rows
    print(label + ': body-write EPIPE retained; no body bytes sent; all three descriptors closed PASS', flush=True)


with tempfile.TemporaryDirectory(prefix='exchange-write-', dir=ROOT / 'build') as temporary:
    directory = Path(temporary)
    compiler = directory / 'bend2'
    shutil.copytree(candidate, compiler)
    effects = compiler / 'effs'
    replace(effects / 'tcp_send_bytes.c', '  return tcp_send_bytes_more(e, w);',
            '  if (w->size == 3 && memcmp(w->data, "abc", 3) == 0) w->code = EPIPE;\n  return tcp_send_bytes_more(e, w);')
    replace(effects / 'tcp_send_bytes.js', '  const b = Uint8Array.from(bytes);',
            '  const b = Uint8Array.from(bytes);\n  if (b.length === 3 && b[0] === 97 && b[1] === 98 && b[2] === 99) return io_tup(socket, io_fail(32));')
    replace(effects / 'socket_duplicate.c', '  return io_tup(e, io_hand(fd), result);',
            '  fprintf(stderr, "DUP %d %d\\n", fd, copy); fflush(stderr);\n  return io_tup(e, io_hand(fd), result);')
    replace(effects / 'socket_close.c', '  close((int)io_hand_v(f[0]));',
            '  fprintf(stderr, "CLOSE %d\\n", (int)io_hand_v(f[0])); fflush(stderr);\n  close((int)io_hand_v(f[0]));')
    replace(effects / 'socket_duplicate.js', '  return io_tup',
            '  process.stderr.write(`DUP ${socket} ${copy}\\n`);\n  return io_tup')
    replace(effects / 'socket_close.js', '  sys.close(socket);',
            '  process.stderr.write(`CLOSE ${socket}\\n`);\n  sys.close(socket);')
    launcher = directory / 'bend'
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(compiler / 'main.ts')) + ' "$@"\n')
    launcher.chmod(0o755)
    environment = dict(os.environ, BEND=str(launcher))
    binary = directory / 'test'
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'tests/http-exchange-write-error.bend', str(binary)], cwd=ROOT, env=environment, check=True)
    javascript = directory / 'test.js'
    subprocess.run([str(launcher), 'tests/http-exchange-write-error.bend', '-o', str(javascript)], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        check([str(binary), '--threads', threads], 'native ' + threads)
    check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun')
