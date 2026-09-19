"""Acquired HTTP byte-lease lifecycle, using real Bend callback/ref effects.

Expected source batches are declared independently of the cursor implementation.
Decoder syntax and wire compatibility have separate response-stream tests.
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
args, expected = [], []


def codes(data):
    return ','.join(map(str, data))


def add(chunks, batches, actions, close_fails=False):
    """A batch supplies events and optionally (release reason, primary error)."""
    inputs = '|'.join('e' if c is None else 'b' + codes(c) for c in chunks)
    args.append(f's{int(close_fails)}/{actions}/{inputs}')
    trace, pending = [], []
    reads = 0
    released = closed = False
    head = 'no-head'
    error = None
    for action in actions:
        if action == 'r':
            if not closed and not released:
                trace.append('release:early:' + head)
                released = True
                error = 'release:close failed' if close_fails else None
            trace.append('return:error:' + error if not closed and error else 'return:ok')
            closed = True
            pending = []
            continue
        if closed:
            trace.append('next:none')
            continue
        while not pending and not released:
            trace.append('read')
            events, terminal = batches[reads]
            reads += 1
            pending.extend(events)
            for event in events:
                if event.startswith('head:'):
                    head = event.split(':')[1]
            if terminal:
                reason, error = terminal
                trace.append('release:' + reason + ':' + head)
                released = True
                if close_fails:
                    error = (error + '+' if error else '') + 'release:close failed'
                    pending = [event for event in pending if not event.startswith('done')]
        if pending:
            trace.append('next:' + pending.pop(0))
        else:
            trace.append('next:error:' + error if error else 'next:none')
            closed = True
    # The fixture retires the cursor before disposing callback handles.
    if not closed and not released:
        trace.append('release:early:' + head)
    expected.append('|'.join(trace))


head = b'HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n'
wire = head + b'abc'
# Every head/body split, including empty reads and remainder delivery, with
# different early-close positions. Source release occurs before queued events.
for split in range(len(wire) + 1):
    chunks = [wire[:split], b'', wire[split:] + b'NEXT']
    batches = []
    offset = 0
    for chunk in chunks:
        end = offset + len(chunk)
        events = ['head:200:body'] if offset < len(head) <= end else []
        body = wire[max(offset, len(head)):min(end, len(wire))]
        if body:
            events.append('data:' + codes(body))
        terminal = None
        if end >= len(wire):
            events.append('done')
            terminal = ('complete:' + codes(chunk[len(wire) - offset:]), None)
        batches.append((events, terminal))
        offset = end
        if terminal:
            break
    for fail in [False, True]:
        for commands in ['', 'rrn', 'nrrn', 'nnrrn', 'nnnrrn', 'nnnnnnrrn']:
            add(chunks, batches, commands, fail)

scenarios = [
    # Closed-delimited clean EOF and read failure are distinct outcomes.
    ([b'HTTP/1.1 200 OK\r\n\r\nabc'], [(['head:200:body', 'data:97,98,99'], None), (['done'], ('eof', None))]),
    ([head, None], [(['head:200:body'], None), ([], ('read-error', 'source:read failed'))]),
    ([None], [([], ('read-error', 'source:read failed'))]),
    ([head + b'a'], [(['head:200:body', 'data:97'], None), ([], ('decode', 'decode'))]),
    ([b'HTTP/1.1'], [([], None), ([], ('decode', 'decode'))]),
    ([b'bad\r\n'], [([], ('decode', 'decode'))]),
    ([b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\naX'], [(['head:200:body', 'data:97'], ('decode', 'decode'))]),
    ([b'HTTP/1.1 103 Early\r\n\r\n', wire], [(['info:103'], None), (['head:200:body', 'data:97,98,99', 'done'], ('complete:', None))]),
    ([b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n0\r\nX: y\r\n\r\nNEXT'], [(['head:200:body', 'data:97', 'done:120:121'], ('complete:78,69,88,84', None))]),
    ([b'HTTP/1.1 205 Reset\r\nContent-Length: 3\r\n\r\nabcNEXT'], [(['head:205:null', 'done'], ('complete:78,69,88,84', None))]),
    ([b'HTTP/1.1 204 Empty\r\n\r\nNEXT'], [(['head:204:null', 'done'], ('complete:78,69,88,84', None))]),
]
for chunks, batches in scenarios:
    for fail in [False, True]:
        for count in range(8):
            add(chunks, batches, 'n' * count + 'rrnn', fail)

# Bytewise reads exercise transitions that produce no event; the header event
# must still stop pulling before the next body byte is requested.
chunks = [bytes([byte]) for byte in wire]
batches = [([], None) for _ in head[:-1]]
batches += [(['head:200:body'], None), (['data:97'], None), (['data:98'], None), (['data:99', 'done'], ('complete:', None))]
for fail in [False, True]:
    for count in range(9):
        add(chunks, batches, 'n' * count + 'rrnn', fail)

(ROOT / 'build').mkdir(exist_ok=True)
negative = ROOT / 'build/http-response-reader-duplicate.bend'
negative.write_text('import Base\nimport ../packages/runtime/src/http-response-reader.bend as Reader\n'
                    'def duplicate(+cursor: Reader.Cursor<String>) -> Reader.Cursor<String> & Reader.Cursor<String>:\n'
                    '  (cursor, cursor)\n')
rejected = subprocess.run([os.environ.get('BEND', str(Path.home() / '.bend/bin/bend')), str(negative)],
                          cwd=ROOT, text=True, capture_output=True, timeout=30)
diagnostic = rejected.stdout + rejected.stderr
assert rejected.returncode != 0 and 'expected : Data' in diagnostic and 'observed : Type' in diagnostic, diagnostic
print('HTTP response cursor duplication rejected by type checker', flush=True)

if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/http-response-reader-runner.bend', 'build/http-response-reader'], cwd=ROOT, check=True)
for threads in ['1', '4']:
    for start in range(0, len(args), 16):
        result = subprocess.run([str(ROOT / 'build/http-response-reader'), '--threads', threads, *args[start:start + 16]], cwd=ROOT, text=True, capture_output=True, check=True, timeout=30)
        actual = result.stdout.splitlines()
        for i, (got, want) in enumerate(zip(actual, expected[start:start + 16], strict=True)):
            assert got == want, (threads, start + i, args[start + i], got, want)
        assert not result.stderr, result.stderr
    print(f'{threads} threads: {len(args)} HTTP lease lifecycle traces PASS')
