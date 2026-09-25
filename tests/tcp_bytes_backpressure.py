"""Linux backpressure test: instrument only a temporary copy of the candidate.

The peer waits for a scheduler read wait and a real send EAGAIN before
sending/draining data. One read EAGAIN is injected to check its retry branch.
No sleeps guess scheduling. Test-only socket sizing makes the write exceed the
kernel buffers. Production effect bodies otherwise remain unchanged.
"""
import concurrent.futures
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shutil
import shlex
import socket
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
assert sys.platform == 'linux', 'test-only socket options currently target Linux'
payload = bytes(range(256)) * 256


def replace_once(path, old, new):
    source = path.read_text()
    assert source.count(old) == 1, (path, old)
    path.write_text(source.replace(old, new))


def check(command, label):
    parked_read = threading.Event()
    parked_write = threading.Event()
    diagnostics = []
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(15)

        def server():
            with listener.accept()[0] as peer:
                peer.settimeout(15)
                assert parked_read.wait(15), 'receive never entered scheduler wait'
                peer.sendall(b'R')
                assert parked_write.wait(15), 'send never reached EAGAIN'
                received = bytearray()
                while len(received) < len(payload):
                    part = peer.recv(3071)
                    assert part, 'premature EOF'
                    received.extend(part)
                assert received == payload, 'bytes lost, duplicated or reordered across send resumption'
                peer.sendall(b'*')
                peer.shutdown(socket.SHUT_WR)
                assert peer.recv(1) == b'', 'unexpected extra bytes'

        server_result = pool.submit(server)
        process = subprocess.Popen([*command, 'p' + str(listener.getsockname()[1])],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def read_diagnostics():
            for line in process.stderr:
                line = line.strip()
                diagnostics.append(line)
                if line == 'WAIT_READ':
                    parked_read.set()
                if line == 'PARK_SEND':
                    parked_write.set()

        reader = pool.submit(read_diagnostics)
        try:
            process.wait(timeout=30)
            stdout = process.stdout.read()
            reader.result(timeout=5)
            assert process.returncode == 0, (process.returncode, diagnostics)
            assert stdout == 'PASS\n', stdout
            server_result.result(timeout=5)
            assert parked_read.is_set() and parked_write.is_set()
            assert 'RETRY_READ' in diagnostics, diagnostics
            print(f'PASS {label}: scheduler read wait, injected read retry, real write EAGAIN, exact 65,536-byte transfer', flush=True)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()


with tempfile.TemporaryDirectory(prefix='tcp-backpressure-', dir=ROOT / 'build') as directory:
    folder = Path(directory)
    compiler = folder / 'bend2'
    shutil.copytree(candidate, compiler)
    effects = compiler / 'effs'
    replace_once(effects / 'tcp_send_bytes.c', '      return io_wait_on(w, fd, POLLOUT, tcp_send_bytes_more);',
                 '      fprintf(stderr, "PARK_SEND\\n"); fflush(stderr);\n      return io_wait_on(w, fd, POLLOUT, tcp_send_bytes_more);')
    replace_once(effects / 'tcp_send_bytes.c', '  u64 cap = 64;',
                 '  int test_buffer = 4096;\n  if (setsockopt((int)w->hand, SOL_SOCKET, SO_SNDBUF, &test_buffer, sizeof(test_buffer))) abort();\n  u64 cap = 64;')
    replace_once(effects / 'tcp_recv_bytes.c', '  return w->code == EAGAIN ?',
                 '  if (w->code == EAGAIN) { fprintf(stderr, "RETRY_READ\\n"); fflush(stderr); }\n  return w->code == EAGAIN ?')
    replace_once(effects / 'tcp_send_bytes.js', '  const fd = socket;',
                 '  const fd = socket;\n  const testBuffer = new Int32Array([4096]);\n  if (sys.setsockopt(fd, 1, 7, sys.ptr(testBuffer), 4)) throw new Error("setsockopt failed");')
    replace_once(effects / 'tcp_send_bytes.js', '          io_park_on(fd, true, k, () => go(at));',
                 '          console.error("PARK_SEND");\n          io_park_on(fd, true, k, () => go(at));')
    replace_once(effects / 'tcp_recv_bytes.js', '        io_park_on(fd, false, k, go);',
                 '        console.error("RETRY_READ");\n        io_park_on(fd, false, k, go);')
    replace_once(compiler / 'comp.ts', '    if (need != 0) {',
                 '    if (need & IO_READ) { fprintf(stderr, "WAIT_READ\\n"); fflush(stderr); }\n    if (need != 0) {')
    replace_once(compiler / 'comp.ts', '        const fd = need.read ? op.args[0] : null;',
                 '        const fd = need.read ? op.args[0] : null;\n        if (need.read) console.error("WAIT_READ");')
    replace_once(effects / 'tcp_recv_bytes.c', 'static Term tcp_recv_bytes_more(Env e, IoWork* w) {',
                 'static int test_read_retry = 1;\nstatic Term tcp_recv_bytes_more(Env e, IoWork* w) {')
    replace_once(effects / 'tcp_recv_bytes.c', 'recv(fd, w->data, (size_t)w->made, 0)',
                 '(test_read_retry-- > 0 ? (errno = EAGAIN, -1) : recv(fd, w->data, (size_t)w->made, 0))')
    replace_once(effects / 'tcp_recv_bytes.js', '  const go = () => {',
                 '  let testFirstRead = true;\n  const go = () => {\n    const injected = testFirstRead;\n    testFirstRead = false;')
    replace_once(effects / 'tcp_recv_bytes.js', 'const n = Number(sys.recv(fd, sys.ptr(b), len, 0));',
                 'const n = injected ? -1 : Number(sys.recv(fd, sys.ptr(b), len, 0));')
    replace_once(effects / 'tcp_recv_bytes.js', 'const code = sys.errno();',
                 'const code = injected ? again : sys.errno();')
    launcher = folder / 'bend'
    # These paths are generated locally, not interpolated user input.
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(compiler / 'main.ts')) + ' "$@"\n')
    launcher.chmod(0o755)
    env = dict(os.environ, BEND=str(launcher))
    output = folder / 'probe'
    source = 'tests/tcp-bytes-backpressure.bend'
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', source, str(output)], cwd=ROOT, env=env, check=True)
    subprocess.run([str(launcher), source, '-o', str(output.with_suffix('.js'))], cwd=ROOT, check=True)
    for threads in ['1', '4']:
        check([str(output), '--threads', threads], 'native threads ' + threads)
    check([str(Path.home() / '.bun/bin/bun'), str(output.with_suffix('.js'))], 'JS backend')
