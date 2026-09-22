"""Isolated socket-control candidate: parked IO, competing cancels, fd retirement.

Instrumentation and small socket buffers are test-only. The installed compiler
is never modified. Pass the directory from prepare-socket-candidate.py.
"""
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
import threading

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()


def replace(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, (path, old)
    path.write_text(text.replace(old, new))


def check(command, label):
    rows = []
    condition = threading.Condition()
    shutdowns = 0
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(15)

        def server():
            for index in range(27):
                with listener.accept()[0] as peer:
                    peer.settimeout(15)
                    if index in [0, 26]:
                        assert peer.recv(1) == b'N'
                        peer.sendall(b'N')
                        assert peer.recv(1) == b''
                    elif index <= 12 or index == 25:
                        assert peer.recv(1) == b'', 'read cancellation wrote data'
                    else:
                        with condition:
                            assert condition.wait_for(lambda: shutdowns >= index, timeout=15), 'shutdown never ran'
                        data = bytearray()
                        while part := peer.recv(4096):
                            data.extend(part)
                        assert len(data) < 65536, 'send was not interrupted'
                        assert data == (bytes(range(256)) * 256)[:len(data)], 'corrupt partial write'

        server_task = pool.submit(server)
        process = subprocess.Popen([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def diagnostics():
            nonlocal shutdowns
            for line in process.stderr:
                row = line.strip().split()
                with condition:
                    rows.append(row)
                    if row[0] == 'SHUT':
                        shutdowns += 1
                    condition.notify_all()

        reader = pool.submit(diagnostics)
        try:
            process.wait(timeout=25)
            output = process.stdout.read()
            reader.result(timeout=3)
            server_task.result(timeout=3)
            assert process.returncode == 0, (label, process.returncode, output, rows)
            assert output == 'PASS socket interruption\n', output
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        groups = []
        for row in rows:
            if row[0] == 'DUP':
                groups.append([row])
            else:
                assert groups, rows
                groups[-1].append(row)
        assert len(groups) == 26, groups
        for index, group in enumerate(groups):
            _, original, copy, cloexec = group[0]
            assert original != copy and cloexec == '1', group
            closed = sorted(r[1] for r in group if r[0] == 'CLOSE')
            if index == 25:
                assert closed == sorted([original, original, copy]), group
            else:
                assert closed == sorted([original, copy]), group
            shuts = [r for r in group if r[0] == 'SHUT']
            if index == 0:
                assert not shuts, group
            else:
                assert shuts == [['SHUT', copy, '0']], group
                if index == 25:
                    continue
                shut_position = next(i for i, r in enumerate(group) if r[0] == 'SHUT')
                expected = 'READ' if index <= 12 else 'WRITE'
                assert any(r == [expected, original] for r in group[:shut_position]), group
        print(f'{label}: 12 parked reads + 12 parked writes cancelled; one winner; 53 descriptor closes; normal disposal and fd reuse PASS', flush=True)


# Additive declarations/effects must not change existing generated runtime code.
for extension in ['c', 'js']:
    outputs = []
    for label, compiler in [('baseline', TOOLCHAIN), ('candidate', CANDIDATE)]:
        output = ROOT / f'build/socket-control-{label}.{extension}'
        subprocess.run([str(Path.home() / '.bun/bin/bun'), str(compiler / 'main.ts'),
                        'tests/tcp-text-baseline.bend', '-o', str(output)], cwd=ROOT, check=True)
        outputs.append(output.read_bytes())
    assert outputs[0] == outputs[1], 'existing TCP output changed: ' + extension
print('Existing TCP fixture: byte-identical generated C and JavaScript', flush=True)

with tempfile.TemporaryDirectory(prefix='socket-control-', dir=ROOT / 'build') as temporary:
    directory = Path(temporary)
    compiler = directory / 'bend2'
    shutil.copytree(CANDIDATE, compiler)
    effects = compiler / 'effs'
    replace(compiler / 'comp.ts', '    if (need != 0) {',
            '    if (need != 0) {\n      if (need & IO_READ) { fprintf(stderr, "READ %u\\n", word); fflush(stderr); }')
    replace(compiler / 'comp.ts', '        const fd = need.read ? op.args[0] : null;',
            '        const fd = need.read ? op.args[0] : null;\n        if (need.read) process.stderr.write("READ " + fd + "\\n");')
    replace(effects / 'socket_duplicate.c', '  return io_tup(e, io_hand(fd), result);',
            '  fprintf(stderr, "DUP %d %d %d\\n", fd, copy, copy >= 0 && (fcntl(copy, F_GETFD) & FD_CLOEXEC) != 0); fflush(stderr);\n  return io_tup(e, io_hand(fd), result);')
    replace(effects / 'tcp_shutdown.c', '  Term result =',
            '  fprintf(stderr, "SHUT %d %d\\n", fd, status); fflush(stderr);\n  Term result =')
    replace(effects / 'socket_close.c', '  close((int)io_hand_v(f[0]));',
            '  fprintf(stderr, "CLOSE %d\\n", (int)io_hand_v(f[0])); fflush(stderr);\n  close((int)io_hand_v(f[0]));')
    replace(effects / 'tcp_recv_bytes.c', '  return w->code == EAGAIN ?',
            '  if (w->code == EAGAIN) { fprintf(stderr, "READ %d\\n", fd); fflush(stderr); }\n  return w->code == EAGAIN ?')
    replace(effects / 'tcp_send_bytes.c', '      return io_wait_on',
            '      fprintf(stderr, "WRITE %d\\n", fd); fflush(stderr);\n      return io_wait_on')
    replace(effects / 'tcp_send_bytes.c', '  u64 cap = 64;',
            '  int small = 4096; setsockopt((int)w->hand, SOL_SOCKET, SO_SNDBUF, &small, sizeof(small));\n  u64 cap = 64;')
    replace(effects / 'socket_duplicate.js', '  return io_tup',
            '  process.stderr.write(`DUP ${socket} ${copy} ${copy >= 0 && (sys.fcntl(copy, 1, 0) & 1) !== 0 ? 1 : 0}\\n`);\n  return io_tup')
    replace(effects / 'tcp_shutdown.js', '  return io_tup',
            '  process.stderr.write(`SHUT ${socket} ${status}\\n`);\n  return io_tup')
    replace(effects / 'socket_close.js', '  sys.close(socket);',
            '  process.stderr.write(`CLOSE ${socket}\\n`);\n  sys.close(socket);')
    replace(effects / 'tcp_recv_bytes.js', '        io_park_on',
            '        process.stderr.write(`READ ${fd}\\n`);\n        io_park_on')
    replace(effects / 'tcp_send_bytes.js', '          io_park_on',
            '          process.stderr.write(`WRITE ${fd}\\n`);\n          io_park_on')
    replace(effects / 'tcp_send_bytes.js', '  const bytes = [];',
            '  const small = new Int32Array([4096]);\n  sys.setsockopt(fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1001 : 7, sys.ptr(small), 4);\n  const bytes = [];')
    launcher = directory / 'bend'
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(compiler / 'main.ts')) + ' "$@"\n')
    launcher.chmod(0o755)
    environment = dict(os.environ, BEND=str(launcher))
    binary = directory / 'test'
    subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/socket-interrupt.bend', str(binary)], cwd=ROOT, env=environment, check=True)
    javascript = directory / 'test.js'
    subprocess.run([str(launcher), 'tests/socket-interrupt.bend', '-o', str(javascript)], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        check([str(binary), '--threads', threads], 'native ' + threads)
    check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun')
