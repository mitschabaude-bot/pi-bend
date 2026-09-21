"""Native HTTP -> SDK-compatible SSE/JSON -> typed Responses event reader."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import threading
import time
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--source', default='tests/openai-http-responses-reader.bend')
parser.add_argument('--prefix', type=Path, default=Path('build/openai-http-reader'))
parser.add_argument('--limit-gib', type=float, default=16)
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(os.environ.get('BEND', ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts')).resolve()
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = args.source
prefix = WORK / args.prefix
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', str(args.limit_gib),
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
scoped = SOURCE == 'tests/openai-scoped-responses-reader.bend'
if scoped:
    with Path(f'{prefix}-audit.c').open('a') as output:
        output.write(r'''
static void __attribute__((destructor)) scoped_timer_audit(void) {
  unsigned live=0,waiting=0;
  for(u32 i=0;i<timer_len;i++){live+=timer_rows[i].live;waiting+=timer_rows[i].waiter!=NULL;}
  fprintf(stderr,"TIMERS %u %u\n",live,waiting);
}
''')
    js = Path(f'{prefix}-audit.js').read_text()
    original = (BEND.parent/'effs/timer.js').read_text()
    assert js.count(original)==1
    needle='  return io_tup(row, row);'
    assert original.count(needle)==1
    changed=original.replace(needle,'  scopedTimerRows.push(row);\n'+needle)
    js=js.replace(original,changed)
    js="const scopedTimerRows=[];process.on('exit',()=>console.error('TIMERS',scopedTimerRows.filter(x=>x.state!==3).length,scopedTimerRows.filter(x=>x.waiter!==null).length));\n"+js
    Path(f'{prefix}-audit.js').write_text(js)

for suffix in ['', '-audit']:
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}{suffix}.c',
                    '-lpthread', '-lm', '-o', str(prefix) + suffix], cwd=WORK, check=True)

def frame(value):
    return ('data: ' + json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n\n').encode()

created = frame({'type': 'response.created', 'response': {'id': 'resp-test'}})
text = frame({'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'hé🙂'})
unknown = frame({'type': 'future.event', 'ignored': 'value'})
done = b'data: [DONE]\n\n'
head = b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n'

def fixed(payload, extra=0):
    return head + f'Content-Length: {len(payload)+extra}\r\n\r\n'.encode() + payload

payload = created + text + unknown + done + b'data: ignored after DONE\n\n'
chunked = b''.join(b'1\r\n' + bytes([byte]) + b'\r\n' for byte in payload) + b'0\r\n\r\n'
normal = ['created:resp-test', 'text:104,233,128578', 'ignored', 'end']
cases = [
    ('fixed', 0, fixed(payload), normal),
    ('chunked', 0, head + b'Transfer-Encoding: chunked\r\n\r\n' + chunked, normal),
    ('eof', 0, head + b'\r\n' + payload, normal),
    ('early', 1, fixed(created, 100), ['created:resp-test', 'abort-hook']),
    ('unread', 2, fixed(b'', 100), []),
    ('cancel', 3, fixed(b'', 100), ['abort-hook', 'end']),
    ('truncated', 0, fixed(created, 100), ['created:resp-test', 'abort-hook', 'error:transport']),
    ('done-truncated', 0, fixed(created + done, 100), ['created:resp-test', 'error:transport']),
    ('invalid-json', 0, fixed(b'data: {\n\n'), ['diagnostic', 'abort-hook', 'error:json']),
    ('invalid-wire', 0, fixed(frame({'type': 'response.created', 'response': {}})), ['abort-hook', 'error:wire']),
    ('api-error', 0, fixed(frame({'error': {'message': 'failed'}})), ['abort-hook', 'error:api']),
    ('empty', 0, fixed(b''), ['end']),
]
if scoped:
    cases.append(('past-header-deadline', 0, fixed(payload), normal))
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
                            if name == 'past-header-deadline':
                                headers, body = wire.split(b'\r\n\r\n', 1)
                                peer.sendall(headers + b'\r\n\r\n')
                                time.sleep(1.15)
                                peer.sendall(body)
                            else:
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
            assert result.stdout.splitlines() == wanted + ['dispose:ok'], (backend, name, result.stdout, wanted)
            expected_audit = ['AUDIT 0 0 0'] + (['TIMERS 0 0'] if scoped else [])
            assert sorted(result.stderr.splitlines()) == (sorted(expected_audit) if audited else []), (backend, name, result.stderr)
            runs.append({'backend': backend, 'audited': audited, 'case': name, 'peer_closed': True, 'passed': True})
        print(backend, 'audited' if audited else 'production', len(cases), 'native Responses reader cases PASS', flush=True)

pending, visited = [WORK / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=WORK, text=True).strip()
new_files = {'packages/runtime/src/http-response.bend', 'packages/runtime/src/http-response-progress.bend',
             'packages/runtime/src/http-response-metadata.bend', 'packages/runtime/src/http-exchange-response.bend',
             'packages/runtime/src/http-body-source.bend', 'packages/runtime/src/http-abort-classification.bend',
             'packages/ai/src/api/openai-http-errors.bend', 'packages/ai/src/api/openai-http-responses-reader.bend',
             'packages/ai/src/api/openai-body-responses-reader.bend', SOURCE}
if SOURCE == 'tests/openai-scoped-responses-reader.bend':
    new_files.update({'packages/ai/src/api/openai-body-responses-reader.bend', 'packages/ai/src/api/openai-responses-scoped-reader.bend'})
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert path.read_bytes() == reference, name
record = {
    'deadline_scope_audited': scoped,
    'scope': 'Real cleartext socket through response ownership, callback byte source, OpenAI SSE/JSON policy and typed Responses wire reader. Native live-channel/parked-IO/socket (fd 0..4095) audit; Bun explicit-channel/live-IO/waiting-IO audit and peer EOF. Finite cases, not universal resource proof.',
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'harness_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), ROOT / 'tests/channel_audit.py']},
    'program_sha256': {suffix: hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']},
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
Path(str(prefix) + '-results.json').write_text(json.dumps(record, indent=2) + '\n')
