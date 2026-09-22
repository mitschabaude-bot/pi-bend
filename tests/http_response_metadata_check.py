"""Differential response projection against actual loopback Node Fetch.

Python orchestrates the peer/oracle and compiled Bend; it supplies no production
behavior. Generic projection/fold invariants live in laws/http-response-metadata.
"""
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'packages/runtime/test/http-response-metadata.bend'
BEND = BEND
BUN = str(Path.home() / '.bun/bin/bun')

def codes(value):
    return ','.join(map(str, value))

def scalars(value):
    return codes(map(ord, value))

rows = []
for method in ['GET', 'HEAD']:
    for status in [200, 201, 204, 205, 299, 300, 304, 400, 429, 500, 599, 999]:
        wire = f'HTTP/1.1 {status} wire reason\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'.encode()
        rows.append((method, wire))
for reason in [b'', b' preserved  ', b'\xc3\xa9', b'\xf0\x9f\x99\x82', b'\xe2\x82', b'\xff', b'\xed\xa0\x80']:
    rows.append(('GET', b'HTTP/1.1 200 ' + reason + b'\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'))
for fields in [
    b'X-Mixed: first\r\nx-mixed: second\r\nX-MIXED: third\r\n',
    b'Set-Cookie: a=1\r\nSet-Cookie: b=2\r\nCookie: a=1\r\ncookie: b=2\r\n',
    b'X-Trailing: \t before\t \r\nX-Empty:\r\nX-Bytes: \xff\xc3\xa9\r\n',
    b'Z: last\r\nA: first\r\nX: middle\r\nA: again\r\n',
]:
    rows.append(('GET', b'HTTP/1.1 200 OK\r\n' + fields + b'Content-Length: 0\r\nConnection: close\r\n\r\n'))
rows += [
    ('GET', b'HTTP/1.1 103 Early Hints\r\nLink: </early>\r\n\r\nHTTP/1.1 200 Final\r\nX-Final: yes\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'),
    ('GET', b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-End\r\nConnection: close\r\n\r\n3\r\nabc\r\n0\r\nX-End: yes\r\n\r\n'),
    ('GET', b'HTTP/1.1 205 Reset\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc'),
    ('GET', b'HTTP/1.1 200 EOF\r\nConnection: close\r\n\r\nabc'),
]

script = r'''
import fs from 'node:fs'; import net from 'node:net';
const rows = JSON.parse(fs.readFileSync(0, 'utf8')); let index = 0;
const server = net.createServer(socket => {
  socket.on('error', () => {});
  socket.once('data', () => socket.end(Buffer.from(rows[index][1])));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const output = [];
try {
  for (index = 0; index < rows.length; index++) {
    const response = await fetch('http://127.0.0.1:' + server.address().port, {
      method: rows[index][0], redirect: 'manual', signal: AbortSignal.timeout(3000)
    });
    output.push({status: response.status, text: response.statusText, ok: response.ok,
      body: response.body !== null, fields: [...response.headers],
      cookies: response.headers.getSetCookie()});
    await response.text();
  }
} finally { await new Promise(resolve => server.close(resolve)); }
console.log(JSON.stringify(output));
'''
observed = json.loads(subprocess.check_output(
    ['node', '--input-type=module', '-e', script], cwd=ROOT, text=True,
    input=json.dumps([(method, list(wire)) for method, wire in rows]), timeout=40))
arguments, expected = [], []
for (method, wire), result in zip(rows, observed, strict=True):
    summary = '#'.join([
        str(result['status']), scalars(result['text']), str(result['ok']).lower(),
        'body' if result['body'] else 'null',
        '|'.join(scalars(name) + ':' + scalars(value) for name, value in result['fields']),
        '|'.join(map(scalars, result['cookies'])),
    ])
    # Every two-chunk partition, empty reads, and one-byte fragmentation.
    partitions = [[wire[:i], b'', wire[i:]] for i in range(len(wire) + 1)]
    partitions.append([bytes([byte]) for byte in wire])
    for chunks in partitions:
        arguments.append(method + ';' + ';'.join(map(codes, chunks)))
        expected.append(summary)

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        subprocess.run([
            sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '8',
            '--stats', f'build/http-response-metadata-{backend}-build.json', '--',
            BEND, SOURCE, '-o', f'build/http-response-metadata.{backend}'
        ], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    'build/http-response-metadata.c', '-lpthread', '-lm',
                    '-o', 'build/http-response-metadata'], cwd=ROOT, check=True)

runs = []
for label, command in [
    ('native-1', [str(ROOT / 'build/http-response-metadata'), '--threads', '1']),
    ('native-4', [str(ROOT / 'build/http-response-metadata'), '--threads', '4']),
    ('bun', [BUN, str(ROOT / 'build/http-response-metadata.js')]),
]:
    for start in range(0, len(arguments), 48):
        result = subprocess.run(command + arguments[start:start + 48], cwd=ROOT,
                                text=True, capture_output=True, check=True, timeout=30)
        assert result.stdout.splitlines() == expected[start:start + 48], (label, start, result.stdout, expected[start:start + 48])
        assert not result.stderr, result.stderr
    runs.append({'backend': label, 'cases': len(arguments), 'passed': True})
    print(label, len(arguments), 'metadata projections PASS', flush=True)

pending, visited = [ROOT / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
visited.add(Path(__file__).resolve())
compiler = Path(BEND).resolve().parent
record = {
    'scope': 'Received response projection through the streaming parser; finite differential cases, not body-owner or IO-lifetime verification.',
    'oracle': subprocess.check_output(['node', '--version'], text=True).strip(),
    'wire_responses': len(rows), 'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/http-response-metadata-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-response-metadata-results.json').write_text(json.dumps(record, indent=2) + '\n')
