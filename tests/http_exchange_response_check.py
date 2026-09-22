"""Response ownership composed with native socket upload/response transport."""
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

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(BEND)
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'tests/http-exchange-response.bend'
prefix = WORK / 'build/http-exchange-response'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '8',
                            '--stats', f'{prefix}-{backend}-build.json', '--',
                            str(BEND), SOURCE, '-o', f'{prefix}.{backend}'],
                           cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    f'{prefix}.c', '-lpthread', '-lm', '-o', str(prefix)], cwd=WORK, check=True)

cases = [
    ('fixed', 0, 'GET', b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabcdef', 'head:200:body', b'abcdef', 'end'),
    ('informational', 0, 'GET', b'HTTP/1.1 103 Early\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabcdef', 'head:200:body', b'abcdef', 'end'),
    ('chunked', 0, 'GET', b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n4\r\ncdef\r\n0\r\nX-End: yes\r\n\r\n', 'head:200:body', b'abcdef', 'end'),
    ('eof', 0, 'GET', b'HTTP/1.1 200 OK\r\n\r\nabcdef', 'head:200:body', b'abcdef', 'end'),
    ('head', 0, 'HEAD', b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n', 'head:200:null', b'', 'end'),
    ('no-content', 0, 'GET', b'HTTP/1.1 204 No Content\r\n\r\n', 'head:204:null', b'', 'end'),
    ('reset-content', 0, 'GET', b'HTTP/1.1 205 Reset\r\nContent-Length: 6\r\n\r\nabcdef', 'head:205:null', b'', 'end'),
    ('early-close', 1, 'GET', b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n', 'head:200:body', b'', None),
    ('cancel-read', 2, 'GET', b'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n', 'head:200:body', b'', 'abort:stop'),
    ('truncated', 0, 'GET', b'HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nabcdef', 'head:200:body', b'abcdef', 'error'),
    ('bad-head', 0, 'GET', b'broken\r\n\r\n', 'start-error', b'', None),
]
runs = []
for backend, command in [
    ('native-1', [str(prefix), '--threads', '1']),
    ('native-4', [str(prefix), '--threads', '4']),
    ('bun', [BUN, str(prefix) + '.js']),
]:
    for name, mode, method, wire, heading, payload, ending in cases:
        errors, peers = [], []
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(10)

            def serve():
                try:
                    with listener.accept()[0] as peer:
                        peer.settimeout(10)
                        request = b''
                        while b'\r\n\r\n' not in request:
                            part = peer.recv(4096)
                            assert part, 'request ended before head'
                            request += part
                        assert request.startswith(f'{method} /body HTTP/1.1\r\n'.encode()), request
                        peer.sendall(wire)
                        if mode == 0:
                            peer.shutdown(socket.SHUT_WR)
                        assert peer.recv(4096) == b'', 'response owner left socket open or wrote extra bytes'
                        peers.append('closed')
                except BaseException as error:
                    errors.append(repr(error))

            thread = threading.Thread(target=serve)
            thread.start()
            try:
                result = subprocess.run(command + [str(listener.getsockname()[1]), str(mode), method], cwd=WORK,
                                        text=True, capture_output=True, check=True, timeout=20)
            finally:
                thread.join(timeout=12)
            assert not thread.is_alive(), (backend, name, 'live peer')
            assert not errors and peers == ['closed'], (backend, name, errors, peers)
        lines = result.stdout.splitlines()
        assert lines[0] == heading, (backend, name, lines)
        actual = bytes(int(value) for line in lines if line.startswith('bytes:') for value in line[6:].split(','))
        assert actual == payload, (backend, name, actual, payload)
        nonbytes = [line for line in lines if not line.startswith('bytes:')]
        expected = [heading]
        if heading != 'start-error':
            if ending is not None:
                expected.append(ending)
            expected.append('closed:end')
        assert nonbytes == expected and not result.stderr, (backend, name, lines, expected, result.stderr)
        runs.append({'backend': backend, 'case': name, 'peer_closed': True, 'passed': True})
    print(backend, len(cases), 'socket response cases PASS', flush=True)

pending, visited = [WORK / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=WORK, text=True).strip()
new_files = {'packages/runtime/src/http-response.bend', 'packages/runtime/src/http-response-progress.bend',
             'packages/runtime/src/http-response-metadata.bend', 'packages/runtime/src/http-exchange-response.bend', SOURCE}
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert path.read_bytes() == reference, name
record = {
    'scope': 'Real loopback HTTP exchange through affine response adapter; peer EOF, body delivery, early close and retained abort reason. No generated-runtime allocation audit in this fixture.',
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-exchange-response-results.json').write_text(json.dumps(record, indent=2) + '\n')
