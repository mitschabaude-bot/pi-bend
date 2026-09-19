"""HTTP responses must settle while a buffered upload is backpressured."""
import concurrent.futures
import os
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()


def replace(path, old, new):
    source = path.read_text()
    assert source.count(old) == 1, (path, old)
    path.write_text(source.replace(old, new))


def check(command, label):
    condition = threading.Condition()
    rows, parked = [], set()
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(15)

        def server():
            for index in range(15):
                with listener.accept()[0] as peer:
                    peer.settimeout(15)
                    head = bytearray()
                    while not head.endswith(b'\r\n\r\n'):
                        part = peer.recv(1)
                        assert part, head
                        head.extend(part)
                    assert head == b'POST / HTTP/1.1\r\ncontent-length: 65536\r\nhost: example.test\r\n\r\n', head
                    with condition:
                        assert condition.wait_for(lambda: index in parked, timeout=15), 'upload never parked'
                    mode = index % 5
                    response = b'HTTP/1.1 413 Content Too Large\r\n'
                    if mode == 0:
                        peer.sendall(response + b'Content-Length: 3\r\n\r\nabc')
                    elif mode == 1:
                        peer.sendall(response + b'Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n')
                    elif mode == 2:
                        peer.sendall(response + b'\r\nabc')
                        peer.shutdown(socket.SHUT_WR)
                    elif mode == 3:
                        peer.sendall(response + b'Content-Length: 3\r\n\r\na')
                        peer.shutdown(socket.SHUT_WR)
                    else:
                        peer.sendall(response + b'Content-Length: 3\r\n\r\n')
                    with condition:
                        assert condition.wait_for(lambda: ['ABORT', str(index)] in rows, timeout=15), 'upload not interrupted on release'
                    data = bytearray()
                    while chunk := peer.recv(4096):
                        data.extend(chunk)
                    assert 0 < len(data) < 65536, len(data)
                    assert data == (bytes(range(256)) * 256)[:len(data)], 'wrong partial upload'

        server_task = pool.submit(server)
        process = subprocess.Popen([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def diagnostics():
            index = -1
            original = None
            closed = 0
            for line in process.stderr:
                row = line.strip().split()
                with condition:
                    if row[0] == 'DUP' and original is None:
                        index += 1
                        original = row[1]
                        closed = 0
                    if row[0] == 'WRITE':
                        parked.add(index)
                    if row[0] == 'SHUT':
                        rows.append(['ABORT', str(index)])
                    rows.append(row)
                    if row[0] == 'CLOSE':
                        closed += 1
                        if closed == 3:
                            original = None
                    condition.notify_all()

        diagnostic_task = pool.submit(diagnostics)
        try:
            process.wait(timeout=30)
            output = process.stdout.read()
            diagnostic_task.result(timeout=3)
            server_task.result(timeout=3)
            assert process.returncode == 0, (label, process.returncode, output, rows)
            lines = output.splitlines()
            assert len(lines) == 15, lines
            for index, line in enumerate(lines):
                expected = ('1;97,98,99;done;eof' if index % 5 < 3 else
                            '1;97;unfinished;decode' if index % 5 == 3 else
                            '1;;unfinished;early')
                assert line == expected, (index, line, expected)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        groups, group = [], []
        for row in rows:
            group.append(row)
            if sum(r[0] == 'CLOSE' for r in group) == 3:
                groups.append(group)
                group = []
        assert len(groups) == 15 and not group, groups
        for index, group in enumerate(groups):
            duplicates = [r for r in group if r[0] == 'DUP']
            assert len(duplicates) == 2, group
            original = duplicates[0][1]
            assert all(r[1] == original for r in duplicates), group
            descriptors = [original, *[r[2] for r in duplicates]]
            assert len(set(descriptors)) == len(descriptors), group
            assert sorted(r[1] for r in group if r[0] == 'CLOSE') == sorted(descriptors), group
            assert len([r for r in group if r[0] == 'SHUT']) == 1, group
            assert ['WRITE', duplicates[1][2]] in group, group
        print(label + ': 15 early HTTP responses during parked uploads; completion/truncation/early-close; 45 descriptors closed PASS', flush=True)


with tempfile.TemporaryDirectory(prefix='http-early-response-', dir=ROOT / 'build') as temporary:
    directory = Path(temporary)
    compiler = directory / 'bend2'
    shutil.copytree(candidate, compiler)
    effects = compiler / 'effs'
    replace(effects / 'tcp_send_bytes.c', '  u64 cap = 64;',
            '  int small = 4096; setsockopt((int)w->hand, SOL_SOCKET, SO_SNDBUF, &small, sizeof(small));\n  u64 cap = 64;')
    replace(effects / 'tcp_send_bytes.c', '      return io_wait_on',
            '      fprintf(stderr, "WRITE %d\\n", fd); fflush(stderr);\n      return io_wait_on')
    replace(effects / 'tcp_send_bytes.js', '  const bytes = [];',
            '  const small = new Int32Array([4096]);\n  sys.setsockopt(fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1001 : 7, sys.ptr(small), 4);\n  const bytes = [];')
    replace(effects / 'tcp_send_bytes.js', '          io_park_on',
            '          process.stderr.write(`WRITE ${fd}\\n`);\n          io_park_on')
    replace(effects / 'socket_duplicate.c', '  return io_tup(e, io_hand(fd), result);',
            '  fprintf(stderr, "DUP %d %d\\n", fd, copy); fflush(stderr);\n  return io_tup(e, io_hand(fd), result);')
    replace(effects / 'socket_duplicate.js', '  return io_tup',
            '  process.stderr.write(`DUP ${socket} ${copy}\\n`);\n  return io_tup')
    replace(effects / 'socket_close.c', '  close((int)io_hand_v(f[0]));',
            '  fprintf(stderr, "CLOSE %d\\n", (int)io_hand_v(f[0])); fflush(stderr);\n  close((int)io_hand_v(f[0]));')
    replace(effects / 'socket_close.js', '  sys.close(socket);',
            '  process.stderr.write(`CLOSE ${socket}\\n`);\n  sys.close(socket);')
    replace(effects / 'tcp_shutdown.c', '  Term result =',
            '  fprintf(stderr, "SHUT %d\\n", fd); fflush(stderr);\n  Term result =')
    replace(effects / 'tcp_shutdown.js', '  return io_tup',
            '  process.stderr.write(`SHUT ${socket}\\n`);\n  return io_tup')
    launcher = directory / 'bend'
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(compiler / 'main.ts')) + ' "$@"\n')
    launcher.chmod(0o755)
    environment = dict(os.environ, BEND=str(launcher))
    binary = directory / 'test'
    subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/http-early-response.bend', str(binary)], cwd=ROOT, env=environment, check=True)
    javascript = directory / 'test.js'
    subprocess.run([str(launcher), 'tests/http-early-response.bend', '-o', str(javascript)], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        check([str(binary), '--threads', threads], 'native ' + threads)
    check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun')
