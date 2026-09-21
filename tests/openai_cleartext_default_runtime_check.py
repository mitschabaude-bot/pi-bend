"""Owned native date/resolver/retry/fetch dependency lifetime over loopback HTTP."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import socket
import struct
import subprocess
import threading
import time
from scoped_session_audit import prepare

ROOT = Path(__file__).resolve().parents[1]
COMPILER = ROOT / 'build/bend-profiles/dns-transport-teles/bend2'
BASE = ROOT / 'build/openai-cleartext-default-runtime'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--backends', nargs='+', choices=['native-1', 'native-4', 'bun'], default=['native-1', 'native-4', 'bun'])
p.add_argument('--audit', action='store_true')
p.add_argument('--prepare-audit', action='store_true')
a = p.parse_args()
if a.prepare_audit:
    prepare(BASE, COMPILER, Path(str(BASE) + '.c').exists())
    raise SystemExit(0)
program = Path(str(BASE) + ('-audit' if a.audit else ''))
commands = {'native-1': [str(program), '--threads', '1'], 'native-4': [str(program), '--threads', '4'], 'bun': [str(Path.home() / '.bun/bin/bun'), str(program) + '.js']}


def number(text):
    high, low = map(int, text.split(':'))
    return struct.unpack('>d', struct.pack('>II', high, low))[0]


runs = []
for backend in a.backends:
    for mode in [0, 1, 2, 4, 5, 6, 7, 8]:
        requests, closed, errors = [], [], []
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(8)
            port = listener.getsockname()[1]

            def serve():
                try:
                    with listener.accept()[0] as peer:
                        peer.settimeout(8)
                        data = b''
                        while b'\r\n\r\n' not in data:
                            part = peer.recv(4096)
                            assert part, 'request ended before headers'
                            data += part
                            assert len(data) < 65536
                        head, body = data.split(b'\r\n\r\n', 1)
                        lines = head.decode().split('\r\n')
                        assert lines[0] == 'POST /responses?x=1 HTTP/1.1', lines
                        headers = dict(line.lower().split(': ', 1) for line in lines[1:])
                        assert headers['host'] == f'127.0.0.1:{port}', headers
                        assert headers['x-fixture'] == 'yes', headers
                        length = int(headers['content-length'])
                        while len(body) < length:
                            part = peer.recv(4096)
                            assert part
                            body += part
                        assert body == '{"message":"héllo"}'.encode(), body
                        requests.append(body.decode())
                        if mode == 4:
                            time.sleep(0.15)
                        elif mode == 5:
                            peer.sendall(b'HTTP/1.1 bad\r\n\r\n')
                        else:
                            peer.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\n' + (b'owned!' if mode == 0 else b''))
                        try:
                            assert peer.recv(4096) == b'', 'unexpected request suffix'
                        except ConnectionResetError:
                            pass
                        closed.append(True)
                except BaseException as error:
                    errors.append(repr(error))

            thread = threading.Thread(target=serve) if mode < 6 else None
            if thread:
                thread.start()
            start = time.time() * 1000
            result = subprocess.run(commands[backend] + [str(mode), str(port)], cwd=ROOT, capture_output=True, text=True, timeout=20)
            end = time.time() * 1000
            if thread:
                thread.join(10)
                assert not thread.is_alive()
            listener.settimeout(0.05)
            try:
                extra, _ = listener.accept()
            except socket.timeout:
                pass
            else:
                extra.close()
                raise AssertionError('unexpected extra request')
        assert not errors and len(requests) == int(mode < 6) and len(closed) == len(requests), (backend, mode, errors, requests, closed)
        assert result.returncode == 0, (backend, mode, result)
        assert sorted(result.stderr.splitlines()) == (['AUDIT 0 0 0', 'TIMERS 0 0'] if a.audit else []), result.stderr
        lines = result.stdout.splitlines()
        if mode >= 7:
            assert lines == (['resolver:71:resolver fixture'] if mode == 7 else ['retry:81:retry fixture']), lines
        else:
            assert len(lines) >= 7, lines
            assert lines[0].startswith('date:') and number(lines[0][5:]) == 784111777000, lines
            assert lines[1] == 'invalid:2146959360:0', lines
            assert lines[2].startswith('random:') and 0 <= number(lines[2][7:]) < 1, lines
            assert lines[3].startswith('now:') and start - 1000 <= number(lines[3][4:]) <= end + 1000, lines
            assert lines[4] == 'sleep:ok', lines
            tail = {0: ['head:200', 'body:owned!'], 1: ['head:200', 'closed'], 2: ['head:200', 'abort:stop'], 4: ['timeout'], 5: ['header-error'], 6: ['tls-required']}[mode]
            assert lines[5:] == tail + ['owner:closed', 'parent:aborted' if mode == 2 else 'parent:live'], lines
        runs.append({'backend': backend, 'audited': a.audit, 'mode': mode, 'trace': lines, 'requests': requests, 'closed': closed})
    print(backend, '8 default runtime cases PASS', flush=True)

pending = [ROOT / 'tests/openai-cleartext-default-runtime.bend']
seen = {Path(__file__).resolve(), ROOT / 'tests/scoped_session_audit.py', ROOT / 'tests/channel_audit.py'}
while pending:
    path = pending.pop().resolve()
    if path in seen:
        continue
    seen.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.M))
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
record = {'scope': __doc__, 'runs': runs, 'sources': {str(path): digest(path) for path in sorted(seen)}, 'program_sha256': {str(path): digest(path) for path in [program, Path(str(program) + '.c'), Path(str(program) + '.js')] if path.exists()}}
Path(str(program) + '-' + ','.join(a.backends) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
