"""Response-prefix acknowledgement followed by a real TCP reset."""
import concurrent.futures
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import shlex
import socket
import struct
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    b'HTTP/1.1 200 OK\r\n\r\nabc',
    b'HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\nabc',
    b'HTTP/1.0 200 OK\r\n\r\nabc',
    b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nabc',
    b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\nabc\r\n',
    b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nabc',
    b'HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\nabc',
]

NODE = r'''
for (let index = 0; index < 7; index++) {
  const response = await fetch(process.argv[1]);
  const reader = response.body.getReader();
  let body = [];
  let completed = false;
  try {
    for (;;) {
      const {value, done} = await reader.read();
      if (done) { completed = true; break; }
      body.push(...value);
      console.log('ready');
    }
  } catch {}
  console.log(`1;${body.join(',')};${completed ? 'done;eof' : 'unfinished;error'}`);
}
'''


def check(command, label, node=False):
    condition = threading.Condition()
    acknowledged = set()
    rows = []
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(15)

        def serve():
            for index, wire in enumerate(CASES):
                with listener.accept()[0] as peer:
                    peer.settimeout(15)
                    request = bytearray()
                    while not request.endswith(b'\r\n\r\n'):
                        part = peer.recv(1)
                        assert part
                        request.extend(part)
                    peer.sendall(wire)
                    with condition:
                        assert condition.wait_for(lambda: index in acknowledged, timeout=15), (label, index, 'no consumed response prefix')
                    peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))

        server = pool.submit(serve)
        port = listener.getsockname()[1]
        argument = f'http://127.0.0.1:{port}/' if node else 'p' + str(port)
        process = subprocess.Popen([*command, argument], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def output():
            index = 0
            for line in process.stdout:
                line = line.rstrip('\n')
                if line == 'ready':
                    with condition:
                        acknowledged.add(index)
                        condition.notify_all()
                else:
                    rows.append(line)
                    index += 1

        reader = pool.submit(output)
        try:
            process.wait(timeout=30)
            reader.result(timeout=3)
            server.result(timeout=3)
            assert process.returncode == 0, (label, rows, process.stderr.read())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        assert len(rows) == 7, (label, rows)
        print(label + ': ' + repr(rows), flush=True)
        return rows


oracle = check(['node', '--input-type=module', '-e', NODE], 'Node Fetch', True)
expected = ['1;97,98,99;' + ('done;eof' if i in [0, 1, 2, 6] else 'unfinished;error') for i in range(7)]
assert oracle == expected, oracle
if len(sys.argv) > 1:
    candidate=Path(sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') else TOOLCHAIN).resolve()
    launcher = ROOT / 'build/http-reset-compiler'
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(candidate / 'main.ts')) + ' "$@"\n')
    launcher.chmod(0o755)
    binary = ROOT / 'build/http-reset'
    javascript = binary.with_suffix('.js')
    if '--no-build' not in sys.argv:
        subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/http-reset.bend', str(binary)], cwd=ROOT, env=dict(os.environ, BEND=str(launcher)), check=True)
        subprocess.run([str(launcher), 'tests/http-reset.bend', '-o', str(javascript)], cwd=ROOT, check=True)
    for label, command in [('native 1', [str(binary), '--threads', '1']), ('native 4', [str(binary), '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), str(javascript)])]:
        actual = check(command, label)
        normalized = [row.replace(';source-error', ';error').replace(';decode', ';error') for row in actual]
        assert normalized == oracle, (label, actual, oracle)
        typed = [value.replace(";error", ";decode" if index in [3, 4] else ";source-error") for index, value in enumerate(oracle)]
        assert actual == typed, (label, actual, typed)
