"""Full cleartext request/response exchange; compare explicit wire fields to Fetch."""
import concurrent.futures
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
launcher = ROOT / 'build/request-exchange-compiler'
launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(Path.home() / '.bun/bin/bun')) + ' ' + shlex.quote(str(candidate / 'main.ts')) + ' "$@"\n')
launcher.chmod(0o755)
environment = dict(os.environ, BEND=str(launcher))
binary = ROOT / 'build/http-request-exchange'
if '--no-native-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/http-request-exchange.bend', str(binary)], cwd=ROOT, env=environment, check=True)
javascript = binary.with_suffix('.js')
subprocess.run([str(launcher), 'tests/http-request-exchange.bend', '-o', str(javascript)], cwd=ROOT, check=True)
body = '{"text":"hé🙂"}'.encode()


def decode_chunks(wire):
    decoded = bytearray()
    position = 0
    while True:
        end = wire.find(b'\r\n', position)
        if end < 0:
            return None
        size = int(wire[position:end], 16)
        position = end + 2
        if len(wire) < position + size + 2:
            return None
        assert wire[position + size:position + size + 2] == b'\r\n'
        if size == 0:
            assert len(wire) == position + 2
            return bytes(decoded)
        decoded.extend(wire[position:position + size])
        position += size + 2


def check(command, label):
    captured = []
    with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        listener.settimeout(10)

        def server():
            for index in range(12):
                with listener.accept()[0] as peer:
                    peer.settimeout(10)
                    buffer = b''
                    while b'\r\n\r\n' not in buffer:
                        chunk = peer.recv(1024)
                        assert chunk and len(buffer) < 16384
                        buffer += chunk
                    head, received = buffer.split(b'\r\n\r\n', 1)
                    lines = head.split(b'\r\n')
                    method = b'DELETE' if index % 2 else b'POST'
                    assert lines[0] == method + b' /v1/responses?x=%C3%A9 HTTP/1.1', lines[0]
                    fields = {}
                    for line in lines[1:]:
                        name, value = line.split(b':', 1)
                        fields.setdefault(name.lower(), []).append(value.lstrip(b' \t'))
                    expected = {b'host': [('127.0.0.1:' + str(listener.getsockname()[1])).encode()], b'content-type': [b'application/json'], b'x-byte': [b'\xff']}
                    if index % 2:
                        expected[b'transfer-encoding'] = [b'chunked']
                        assert b'content-length' not in fields, fields
                    else:
                        expected[b'content-length'] = [str(len(body)).encode()]
                        assert b'transfer-encoding' not in fields, fields
                    assert {key: fields.get(key) for key in expected} == expected, fields
                    if index % 2:
                        decoded = decode_chunks(received)
                        while decoded is None:
                            chunk = peer.recv(1024)
                            assert chunk
                            received += chunk
                            decoded = decode_chunks(received)
                        received = decoded
                    else:
                        while len(received) < len(body):
                            chunk = peer.recv(1024)
                            assert chunk
                            received += chunk
                    assert received == body, received
                    captured.append((lines[0], {**expected, b'host': [b'<endpoint authority>']}, received))
                    peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK')
                    assert peer.recv(1) == b''

        future = pool.submit(server)
        result = subprocess.run([*command, 'p' + str(listener.getsockname()[1])], cwd=ROOT, text=True, capture_output=True, timeout=20)
        future.result(timeout=3)
        assert result.returncode == 0, (label, result.stdout, result.stderr)
        assert result.stdout == 'PASS request exchange\n', result.stdout
        assert not result.stderr, result.stderr
    print(label + ': 12 complete fixed/chunked JSON exchanges PASS', flush=True)
    return captured


oracle = r'''
const port=process.argv[1].slice(1);
for(let i=0;i<12;i++){
 const r=await fetch('http://127.0.0.1:'+port+'/v1/responses?x=%C3%A9',{
 method:i%2?'delete':'post',headers:{'content-type':'application/json','x-byte':'\xff',...(i%2?{'content-length':'0'}:{})},body:'{"text":"hé🙂"}',signal:AbortSignal.timeout(3000)});
 if(r.status!==200 || await r.text()!=='OK') throw Error('wrong response');
}
console.log('PASS request exchange');
'''
reference = check(['node', '--input-type=module', '-e', oracle], 'Node Fetch')
for threads in ['1', '4']:
    assert check([str(binary), '--threads', threads], 'native ' + threads) == reference
assert check([str(Path.home() / '.bun/bin/bun'), str(javascript)], 'Bun') == reference
