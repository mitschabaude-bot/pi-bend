"""Lazy native Responses acquisition: ordering, wire reuse, hooks and ownership."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import threading
from scoped_session_audit import prepare

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'build/openai-owned-acquire'
COMPILER = ROOT / 'build/bend-profiles/dns-transport-teles/bend2'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--backends', nargs='+', choices=['native-1', 'native-4', 'bun'], default=['native-1', 'native-4', 'bun'])
p.add_argument('--audit', action='store_true')
p.add_argument('--prepare-audit', action='store_true')
a = p.parse_args()
if a.prepare_audit:
    native = Path(str(BASE) + '.c').exists()
    prepare(BASE, COMPILER, native)
    tree = ast.parse((ROOT / 'tests/resolver_file_check.py').read_text())
    audit = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'audit' for t in n.targets))
    if native:
        path = Path(str(BASE) + '-audit.c')
        path.write_text(path.read_text() + audit)
    path = Path(str(BASE) + '-audit.js')
    path.write_text("""import {readdirSync as auditList,readlinkSync as auditLink} from 'node:fs';
process.on('exit',()=>{let live=0;const root=process.env.PI_BEND_FILE_TEST_ROOT;
for(const fd of auditList('/proc/self/fd')) {try {const target=auditLink('/proc/self/fd/'+fd);if(target===root||target.startsWith(root+'/'))live++;}catch{}}
console.error('FILES '+live);});
""" + path.read_text())
    raise SystemExit(0)

program = Path(str(BASE) + ('-audit' if a.audit else ''))
commands = {'native-1': [str(program), '--threads', '1'], 'native-4': [str(program), '--threads', '4'], 'bun': [str(Path.home() / '.bun/bin/bun'), str(program) + '.js']}
runs = []
network = {0, 1, 2, 3, 11, 14}
early = {4, 5, 6, 7, 8, 10, 12, 13}
failures = {3: 'response:closed', 4: 'credential:fixture', 5: 'retry-options', 6: 'payload', 7: 'url', 8: 'aborted', 9: 'configuration', 10: 'aborted', 12: 'header', 13: 'nonfinite'}
with tempfile.TemporaryDirectory(prefix='pi-bend-owned-acquire-') as temp:
    root = Path(temp)
    (root / 'resolver').write_text('nameserver 127.0.0.1\noptions ndots:1 timeout:1 attempts:1\n')
    (root / 'hosts').write_text('127.0.0.1 fixture.invalid\n')
    (root / 'bad-resolver').write_text('options ndots:bad\n')
    os.mkfifo(root / 'blocked')
    environment = {**os.environ, 'RES_OPTIONS': '', 'LOCALDOMAIN': '', 'PI_BEND_FILE_TEST_ROOT': temp}
    for backend in a.backends:
        for mode in range(15):
            requests, closed, errors = [], [], []
            stop = threading.Event()
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                listener.listen()
                listener.settimeout(.1)
                port = listener.getsockname()[1]

                def serve():
                    try:
                        while not stop.is_set():
                            try:
                                peer, _ = listener.accept()
                            except socket.timeout:
                                continue
                            with peer:
                                peer.settimeout(10)
                                data = b''
                                while b'\r\n\r\n' not in data:
                                    part = peer.recv(4096)
                                    assert part, 'EOF before request headers'
                                    data += part
                                    assert len(data) < 65536
                                head, body = data.split(b'\r\n\r\n', 1)
                                lines = head.decode().split('\r\n')
                                assert lines[0] == 'POST /v1/responses HTTP/1.1', lines
                                headers = dict(line.lower().split(': ', 1) for line in lines[1:])
                                assert headers['authorization'] == 'bearer fixture-key'
                                assert headers['x-fixture'] == 'yes'
                                length = int(headers['content-length'])
                                while len(body) < length:
                                    part = peer.recv(4096)
                                    assert part
                                    body += part
                                assert body == {1: b'null', 2: b'9'}.get(mode, b'"original"'), body
                                requests.append(body.decode())
                                if mode == 11 and len(requests) == 1:
                                    peer.sendall(b'HTTP/1.1 503 Busy\r\nContent-Length: 0\r\nretry-after-ms: 0\r\nConnection: close\r\n\r\n')
                                else:
                                    # Deliberately incomplete body: release must close the
                                    # open response, rather than rely on natural EOF.
                                    peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\n')
                                try:
                                    assert peer.recv(4096) == b'', 'unexpected request suffix'
                                except ConnectionResetError:
                                    pass
                                closed.append(True)
                    except BaseException as error:
                        errors.append(repr(error))

                thread = threading.Thread(target=serve)
                thread.start()
                resolver = root / ('blocked' if mode in early else 'bad-resolver' if mode == 9 else 'resolver')
                hosts = root / ('blocked' if mode in early or mode == 9 else 'hosts')
                try:
                    result = subprocess.run(commands[backend] + [str(mode), str(port), str(resolver), str(hosts)], cwd=ROOT, env=environment, capture_output=True, text=True, timeout=25)
                finally:
                    stop.set()
                    thread.join(12)
                assert not thread.is_alive()
            count = 2 if mode == 11 else int(mode in network)
            assert not errors and len(requests) == count and len(closed) == count, (backend, mode, errors, requests, closed)
            assert result.returncode == 0, (backend, mode, result)
            assert sorted(result.stderr.splitlines()) == (['AUDIT 0 0 0', 'FILES 0', 'TIMERS 0 0'] if a.audit else []), result.stderr
            expected = ['prepare']
            if mode not in {4, 5}:
                expected += ['payload']
            if mode in network:
                expected += ['response:200']
            expected += ['error:' + failures[mode]] if mode in failures else ['metadata:original', 'closed']
            expected += ['borrowed-hooks', 'payload', 'response:200', 'parent:aborted' if mode in {8, 10} else 'parent:live']
            assert result.stdout.splitlines() == expected, (backend, mode, result.stdout, expected)
            runs.append({'backend': backend, 'audited': a.audit, 'mode': mode, 'trace': expected, 'requests': requests, 'closed': closed})
        print(backend, '15 owned acquisition cases PASS', flush=True)

pending = [ROOT / 'tests/openai-owned-acquire.bend']
seen = {Path(__file__).resolve(), ROOT / 'tests/scoped_session_audit.py', ROOT / 'tests/channel_audit.py', ROOT / 'tests/resolver_file_check.py'}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
record = {'scope': __doc__, 'runs': runs, 'sources': {str(path): digest(path) for path in sorted(seen)}, 'program_sha256': {str(path): digest(path) for path in [program, Path(str(program) + '.c'), Path(str(program) + '.js')] if path.exists()}}
Path(str(program) + '-' + ','.join(a.backends) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
