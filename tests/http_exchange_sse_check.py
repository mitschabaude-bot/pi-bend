"""Native HTTP socket -> owned byte source -> actual SSE reader."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import socket
import subprocess
import sys
import threading
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(BEND)
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'tests/http-exchange-sse.bend'
prefix = WORK / 'build/http-exchange-sse'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '8',
                            '--stats', f'{prefix}-{backend}-build.json', '--', str(BEND), SOURCE, '-o', f'{prefix}.{backend}'],
                           cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)

c = Path(f'{prefix}.c').read_text()
Path(f'{prefix}-audit.c').write_text(c + r'''
static void __attribute__((destructor)) exchange_sse_audit(void) {
  unsigned channels=0,sockets=0;
  for(u32 i=0;i<chan_len;i++)channels+=chan_rows[i].live;
  for(int fd=0;fd<4096;fd++){int type;socklen_t n=sizeof(type);if(getsockopt(fd,SOL_SOCKET,SO_TYPE,&type,&n)==0)sockets++;}
  fprintf(stderr,"AUDIT %u %u %u\n",channels,io_park.head!=NULL,sockets);
}
''')
Path(f'{prefix}-audit.js').write_text(instrument(Path(f'{prefix}.js').read_text()))
for suffix in ['', '-audit']:
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c',
                    '-lpthread', '-lm', '-o', str(prefix) + suffix], cwd=WORK, check=True)

payload = 'data: hé🙂\n\ndata: two\n\n'.encode()
first = 'data: hé🙂\n\n'.encode()
events = ['data:104,233,128578', 'data:116,119,111']
head = b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n'
chunked = b''.join(b'1\r\n' + bytes([byte]) + b'\r\n' for byte in payload) + b'0\r\nX-End: yes\r\n\r\n'
cases = [
    ('fixed', 0, head + f'Content-Length: {len(payload)}\r\n\r\n'.encode() + payload, events + ['end']),
    ('chunked', 0, head + b'Transfer-Encoding: chunked\r\n\r\n' + chunked, events + ['end']),
    ('eof', 0, head + b'\r\n' + payload, events + ['end']),
    ('early', 1, head + b'Content-Length: 100\r\n\r\n' + first, events[:1]),
    ('unread', 2, head + b'Content-Length: 100\r\n\r\n', []),
    ('truncated', 0, head + b'Content-Length: 100\r\n\r\n' + first, events[:1] + ['error:transport']),
    ('unfinished-event', 0, head + b'Content-Length: 14\r\n\r\ndata: pending\n', ['end']),
]
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [
        ('native-1', [str(prefix) + suffix, '--threads', '1']),
        ('native-4', [str(prefix) + suffix, '--threads', '4']),
        ('bun', [BUN, str(prefix) + suffix + '.js']),
    ]:
        for name, mode, wire, wanted in cases:
            errors, peers = [], []
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0)); listener.listen(); listener.settimeout(10)

                def serve():
                    try:
                        with listener.accept()[0] as peer:
                            peer.settimeout(10)
                            request = b''
                            while b'\r\n\r\n' not in request:
                                part = peer.recv(4096)
                                assert part, 'request ended before head'
                                request += part
                            assert request.startswith(b'GET /sse HTTP/1.1\r\n'), request
                            peer.sendall(wire)
                            if mode == 0:
                                peer.shutdown(socket.SHUT_WR)
                            assert peer.recv(4096) == b'', 'owner did not close peer or wrote extra bytes'
                            peers.append('closed')
                    except BaseException as error:
                        errors.append(repr(error))

                thread = threading.Thread(target=serve); thread.start()
                try:
                    result = subprocess.run(command + [str(listener.getsockname()[1]), str(mode)], cwd=WORK,
                                            text=True, capture_output=True, check=True, timeout=20)
                finally:
                    thread.join(timeout=12)
                assert not thread.is_alive() and not errors and peers == ['closed'], (backend, name, errors, peers)
            assert result.stdout.splitlines() == wanted + ['reader-close:ok', 'dispose:ok'], (backend, name, result.stdout, wanted)
            assert result.stderr == ('AUDIT 0 0 0\n' if audited else ''), (backend, name, result.stderr)
            runs.append({'backend': backend, 'audited': audited, 'case': name, 'peer_closed': True, 'passed': True})
        print(backend, 'audited' if audited else 'production', len(cases), 'socket/SSE cases PASS', flush=True)

pending, visited = [WORK / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
record = {
    'scope': 'Real cleartext socket through response ownership, callback byte source and SSE reader. Native live-channel/parked-IO/socket (fd 0..4095) audit; Bun explicit-channel/live-IO/waiting-IO audit and peer EOF. Finite cases, not universal resource proof.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'harness_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), ROOT / 'tests/channel_audit.py']},
    'program_sha256': {suffix: hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']},
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-exchange-sse-results.json').write_text(json.dumps(record, indent=2) + '\n')
