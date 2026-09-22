"""Owned native HTTP bytes/text/JSON consumption and resource retirement."""
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
SOURCE = 'tests/http-body-consume-native.bend'
prefix = WORK / 'build/http-body-consume-native'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '16',
                            '--stats', f'{prefix}-{backend}-build.json', '--', str(BEND), SOURCE, '-o', f'{prefix}.{backend}'],
                           cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)

c = Path(f'{prefix}.c').read_text()
Path(f'{prefix}-audit.c').write_text(c + r'''
static void __attribute__((destructor)) openai_http_reader_audit(void) {
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

head=b'HTTP/1.1 200 OK\r\n'
def fixed(payload, extra=0):
    return head+f'Content-Length: {len(payload)+extra}\r\n\r\n'.encode()+payload

def scalars(value): return ','.join(str(ord(c)) for c in value)
text='hé🙂'; payload=text.encode(); json_bytes=b'{"x":[true,null,"hi"]}'
cases=[
    ('fixed-bytes',0,'GET',len(payload),fixed(payload),'bytes:'+','.join(map(str,payload)),False),
    ('fixed-text',1,'GET',len(payload),fixed(payload),'text:'+scalars(text),False),
    ('fixed-json',2,'GET',len(json_bytes),fixed(json_bytes),'json:{120=[true;null;s104,105;];}',False),
    ('bom-text',1,'GET',len(payload)+3,fixed(b'\xef\xbb\xbf'+payload),'text:'+scalars(text),False),
    ('chunked-text',1,'GET',len(payload),head+b'Transfer-Encoding: chunked\r\n\r\n'+b''.join(b'1\r\n'+bytes([x])+b'\r\n' for x in payload)+b'0\r\nx-end: yes\r\n\r\n','text:'+scalars(text),False),
    ('eof-text',1,'GET',len(payload),head+b'\r\n'+payload,'text:'+scalars(text),False),
    ('head-null',0,'HEAD',0,fixed(payload),'bytes:',False),
    ('no-content',1,'GET',0,b'HTTP/1.1 204 No Content\r\n\r\n','text:',False),
    ('empty-text',1,'GET',0,fixed(b''),'text:',False),
    ('empty-json',2,'GET',0,fixed(b''),'error:json',False),
    ('truncated',0,'GET',100,fixed(payload,10),'error:transport',False),
    ('limit-early',0,'GET',1,fixed(payload,100),'error:limit',True),
    ('limit-json',2,'GET',1,fixed(json_bytes,100),'error:limit',True),
    ('invalid-utf8',1,'GET',100,fixed(b'\xc0\xaf'),'error:utf8',False),
    ('invalid-json',2,'GET',100,fixed(b'[1,]'),'error:json',False),
]
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [
        ('native-1', [str(prefix) + suffix, '--threads', '1']),
        ('native-4', [str(prefix) + suffix, '--threads', '4']),
        ('bun', [BUN, str(prefix) + suffix + '.js']),
    ]:
        for name, mode, method, budget, wire, wanted, hold in cases:
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
                            assert request.startswith((method+' /body HTTP/1.1\r\n').encode()), request
                            peer.sendall(wire)
                            if not hold:
                                peer.shutdown(socket.SHUT_WR)
                            # Early consumer failure can close with unread receive bytes:
                            # TCP reset and EOF both establish peer-side closure.
                            try:
                                assert peer.recv(4096) == b'', 'owner did not close peer or wrote extra bytes'
                                peers.append('eof')
                            except ConnectionResetError:
                                peers.append('reset')
                    except BaseException as error:
                        errors.append(repr(error))

                thread = threading.Thread(target=serve); thread.start()
                try:
                    result = subprocess.run(command + [str(listener.getsockname()[1]), str(mode), method, str(budget)], cwd=WORK,
                                            text=True, capture_output=True, check=True, timeout=20)
                finally:
                    thread.join(timeout=12)
                assert not thread.is_alive() and not errors and len(peers) == 1, (backend, name, errors, peers)
            assert result.stdout.splitlines() == [wanted], (backend, name, result.stdout, wanted)
            assert result.stderr == ('AUDIT 0 0 0\n' if audited else ''), (backend, name, result.stderr)
            runs.append({'backend': backend, 'audited': audited, 'case': name, 'peer_closed': True, 'peer_close': peers[0], 'passed': True})
        print(backend, 'audited' if audited else 'production', len(cases), 'owned native body cases PASS', flush=True)

pending, visited = [WORK / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=WORK, text=True).strip()
new_files = {'packages/runtime/src/http-transport-callbacks.bend', 'packages/runtime/src/http-body-consume.bend', 'packages/runtime/src/http-response.bend', 'packages/runtime/src/http-response-progress.bend',
             'packages/runtime/src/http-response-metadata.bend', 'packages/runtime/src/http-exchange-response.bend',
             'packages/runtime/src/http-body-source.bend', 'packages/runtime/src/http-abort-classification.bend',
             'packages/runtime/src/bounded-bytes.bend', 'packages/runtime/src/http-body-buffer.bend',
             'packages/runtime/src/http-body-consume.bend', 'packages/runtime/test/http-body-consume.bend',
             'packages/runtime/test/http-response.bend', SOURCE}
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert path.read_bytes() == reference, name
record = {
    'scope': 'Real cleartext HTTP bytes/text/JSON consumption through owned bodies. Fixed/chunked/EOF framing, suppressed/empty bodies, truncation, immediate limit close and strict decode errors. Native channel/park/socket audit and Bun channel/IO audit plus peer closure; finite cases, not a universal resource proof.',
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'harness_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), ROOT / 'tests/channel_audit.py']},
    'program_sha256': {suffix: hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']},
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-body-consume-native-results.json').write_text(json.dumps(record, indent=2) + '\n')
