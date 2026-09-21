"""Native HTTP -> SSE/JSON -> canonical assistant-message processing, checked against pi."""
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
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
parser.add_argument('--prefix', type=Path, default=Path('build/openai-http-process'))
args = parser.parse_args()
WORK = args.worktree.resolve()
BEND = Path(os.environ.get('BEND', ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts')).resolve()
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'tests/openai-http-process.bend'
prefix = WORK / args.prefix
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '24',
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

def frame(value):
    return ('data: ' + json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n\n').encode()

created = {'type': 'response.created', 'response': {'id': 'resp-test'}}
item = {'type': 'message', 'id': 'msg-test', 'role': 'assistant', 'content': []}
added = {'type': 'response.output_item.added', 'output_index': 0, 'item': item}
delta = {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'hé🙂'}
delta2 = {**delta, 'delta': '!'}
ended = {'type': 'response.output_item.done', 'output_index': 0, 'item': {**item, 'content': [{'type': 'output_text', 'text': 'hé🙂!'}]}}
completed = {'type': 'response.completed', 'response': {'id': 'resp-final', 'status': 'completed', 'usage': {'input_tokens': 20, 'output_tokens': 5, 'total_tokens': 25, 'input_tokens_details': {'cached_tokens': 3, 'cache_write_tokens': 2}}}}
incomplete = {'type': 'response.incomplete', 'response': {'id': 'resp-final', 'status': 'incomplete', 'incomplete_details': {'reason': 'max_output_tokens'}}}
unknown = {'type': 'future.event', 'ignored': 'value'}
done = b'data: [DONE]\n\n'
head = b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n'
def fixed(payload, extra=0):
    return head + f'Content-Length: {len(payload)+extra}\r\n\r\n'.encode() + payload

def encoded(events):
    return b''.join(map(frame, events))

normal = [created, added, delta, delta2, ended, unknown, completed]
partial = [created, added, delta]
cases = []
def add(name, events, *, framing='fixed', tail=done, extra=0, sink=False, read=None, hooks=()):
    payload = encoded(events) + tail
    wire = (head + b'Transfer-Encoding: chunked\r\n\r\n' + b''.join(b'1\r\n' + bytes([x]) + b'\r\n' for x in payload) + b'0\r\n\r\n' if framing == 'chunked'
            else head + b'\r\n' + payload if framing == 'eof' else fixed(payload, extra))
    cases.append({'name': name, 'events': events, 'wire': wire, 'sinkFail': sink, 'readError': read, 'hooks': list(hooks)})
for framing in ['fixed', 'chunked', 'eof']:
    add(framing, normal, framing=framing, tail=done+b'data: ignored after DONE\n\n')
add('incomplete', [created, added, delta, incomplete])
add('missing-terminal', partial)
add('empty', [], tail=b'')
add('sink-failure', normal, sink=True, hooks=['abort-hook'])
add('provider-failure', partial+[{'type': 'response.failed', 'response': {'status': 'failed', 'error': {'code': 'failed', 'message': 'failed'}}}], hooks=['abort-hook'])
add('truncated', partial, tail=b'', extra=100, read='transport', hooks=['abort-hook'])
add('done-truncated', partial, extra=100, read='transport')
add('terminal-truncated', normal, tail=b'', extra=100, read='transport', hooks=['abort-hook'])
add('terminal-done-truncated', normal, extra=100, read='transport')
add('invalid-json', partial, tail=b'data: {\n\n', read='json', hooks=['diagnostic', 'abort-hook'])
add('invalid-wire', partial, tail=frame({'type': 'response.created', 'response': {}}), read='wire', hooks=['abort-hook'])
add('api-error', partial, tail=frame({'error': {'message': 'failed'}}), read='api', hooks=['abort-hook'])
oracle_input = [{k: c[k] for k in ['events', 'sinkFail', 'readError']} for c in cases]
reference_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT.parent/'pi-mono', text=True).strip()
assert reference_commit.startswith('46c9de402'), reference_commit
expected = json.loads(subprocess.check_output(['node', 'tests/openai_http_process_reference.mts'], input=json.dumps(oracle_input), text=True, cwd=ROOT))
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for backend, command in [
        ('native-1', [str(prefix) + suffix, '--threads', '1']),
        ('native-4', [str(prefix) + suffix, '--threads', '4']),
        ('bun', [BUN, str(prefix) + suffix + '.js']),
    ]:
        for case, reference in zip(cases, expected):
            name, mode, wire = case['name'], int(case['sinkFail']), case['wire']
            wanted = reference['trace'] + case['hooks'] + [reference['output'], reference['result']]
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
                    result = subprocess.run(command + [str(listener.getsockname()[1]), str(mode)], cwd=WORK,
                                            text=True, capture_output=True, check=True, timeout=20)
                finally:
                    thread.join(timeout=12)
                assert not thread.is_alive() and not errors and len(peers) == 1, (backend, name, errors, peers)
            assert result.stdout.splitlines() == wanted + ['dispose:ok'], (backend, name, result.stdout, wanted)
            assert result.stderr == ('AUDIT 0 0 0\n' if audited else ''), (backend, name, result.stderr)
            runs.append({'backend': backend, 'audited': audited, 'case': name, 'peer_closed': True, 'peer_close': peers[0], 'passed': True})
        print(backend, 'audited' if audited else 'production', len(cases), 'native assistant processing cases PASS', flush=True)

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
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert path.read_bytes() == reference, name
record = {
    'scope': 'Real cleartext HTTP through canonical assistant processor, compared to actual pinned pi processor with immutable emission snapshots. Text/event ordering, response IDs, usage/cost, terminal and read/sink failures; native channel/park/socket audit, Bun channel/IO audit and peer closure (EOF or reset). Finite integration cases, not a universal resource proof.',
    'reference_commit': reference_commit,
    'reference_sha256': {name: hashlib.sha256((ROOT.parent/'pi-mono'/name).read_bytes()).hexdigest() for name in ['packages/ai/src/api/openai-responses-shared.ts', 'packages/ai/src/api/constrained-sampling.ts', 'packages/ai/src/models.ts', 'packages/ai/src/utils/json-parse.ts']},
    'reference_outputs': expected,
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'harness_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), ROOT / 'tests/channel_audit.py', ROOT / 'tests/openai_http_process_reference.mts', ROOT / 'tests/responses_stream_reference.mts']},
    'program_sha256': {suffix: hashlib.sha256(Path(str(prefix)+suffix).read_bytes()).hexdigest() for suffix in ['', '.c', '.js', '-audit', '-audit.c', '-audit.js']},
    'compiler_command': str(BEND),
    'compiler_sha256': {name: hashlib.sha256((BEND.parent / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
Path(str(prefix)+'-results.json').write_text(json.dumps(record, indent=2) + '\n')
