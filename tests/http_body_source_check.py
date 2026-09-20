"""Owned HTTP body -> actual SSE reader, with emitted-runtime channel audits."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts'))
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'packages/runtime/test/http-body-source.bend'
arguments, expected = [], []

def codes(value):
    return ','.join(map(str, value))

def chunk(value):
    return 'b' + codes(value)

def add(fails, actions, events, trace):
    arguments.append(';'.join([str(int(fails)), actions, *events]))
    expected.extend(['case', *trace])

add(False, 'p', ['b65', 'b66', 'eunread'], ['read:b65', 'read:b66', 'parallel:65', 'parallel:66', 'close', 'dispose:ok'])

one = chunk(b'data: one\n\n')
two = chunk(b'data: one\n\ndata: two\n\n')
for fails in [False, True]:
    close = 'error:cleanup' if fails else 'ok'
    suffix = '+cleanup' if fails else ''
    for actions in ['', 'c']:
        add(fails, actions, ['eunread'], (['end'] if actions else []) + ['reader-close:ok', 'close', 'dispose:' + close])
    add(fails, 'n', [two, 'eunread'], [
        'read:' + two, 'data:111,110,101', 'close', 'reader-close:' + close, 'dispose:ok'])
    add(fails, 'nnnn', [two, 'cfin', 'eunread'], [
        'read:' + two, 'data:111,110,101', 'data:116,119,111', 'read:cfin', 'close',
        'error:cleanup' if fails else 'end', 'end', 'reader-close:ok', 'dispose:ok'])
    add(fails, 'nn', [one, 'ebroken', 'eunread'], [
        'read:' + one, 'data:111,110,101', 'read:ebroken', 'close',
        'error:transport:broken' + suffix, 'reader-close:ok', 'dispose:ok'])
    add(fails, 'nn', ['ebroken', 'eunread'], [
        'read:ebroken', 'close', 'error:transport:broken' + suffix, 'end', 'reader-close:ok', 'dispose:ok'])
    partial = chunk(b'data: unfinished\n')
    add(fails, 'nn', [partial, 'cfin'], [
        'read:' + partial, 'read:cfin', 'close', 'error:cleanup' if fails else 'end',
        'end', 'reader-close:ok', 'dispose:ok'])

# Actual UTF-8/SSE decoding across every byte boundary; no hand-written parser
# supplies the expected event. Include empty HTTP chunks between the halves.
wire = 'data: hé🙂\r\n\r\n'.encode()
for split in range(len(wire) + 1):
    chunks = [chunk(wire[:split]), 'b', chunk(wire[split:])]
    # If the first half already contains the complete frame, the reader emits
    # it before pulling the remaining empty chunks on the next call.
    first = ['read:' + chunks[0]]
    later = ['read:' + value for value in chunks[1:]]
    trace = first + (['data:104,233,128578'] + later if split == len(wire) else later + ['data:104,233,128578'])
    add(False, 'nn', chunks + ['cfin'], trace + ['read:cfin', 'close', 'end', 'reader-close:ok', 'dispose:ok'])

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        with (ROOT / f'build/http-body-source-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                            '--stats', f'build/http-body-source-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/http-body-source.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)

c = (ROOT / 'build/http-body-source.c').read_text()
audit = r'''
static void __attribute__((destructor)) body_source_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++) channels += chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u\n",channels,io_park.head!=NULL);
}
'''
(ROOT / 'build/http-body-source-audit.c').write_text(c + audit)
(ROOT / 'build/http-body-source-audit.js').write_text(instrument((ROOT / 'build/http-body-source.js').read_text()))
for suffix in ['', '-audit']:
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    f'build/http-body-source{suffix}.c', '-lpthread', '-lm', '-o', f'build/http-body-source{suffix}'], cwd=ROOT, check=True)
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for label, command in [
        ('native-1', [str(ROOT / ('build/http-body-source' + suffix)), '--threads', '1']),
        ('native-4', [str(ROOT / ('build/http-body-source' + suffix)), '--threads', '4']),
        ('bun', [BUN, str(ROOT / ('build/http-body-source' + suffix + '.js'))]),
    ]:
        run = subprocess.run(command + arguments, cwd=ROOT, text=True, capture_output=True, timeout=60, check=True)
        actual = run.stdout.splitlines()
        # Task acquisition order is unspecified. Require both distinct chunks;
        # keep all read/close traces and every other line in exact order.
        for i in range(len(actual) - 1):
            if actual[i].startswith('parallel:') and actual[i+1].startswith('parallel:'):
                actual[i:i+2] = sorted(actual[i:i+2])
        if actual != expected:
            for i, (observed, wanted) in enumerate(zip(actual, expected)):
                if observed != wanted:
                    raise AssertionError((label, i, actual[max(0,i-8):i+8], expected[max(0,i-8):i+8]))
            raise AssertionError((label, len(actual), len(expected)))
        want = ('AUDIT 0 0 0\n' if label == 'bun' else 'AUDIT 0 0\n') if audited else ''
        assert run.stderr == want, (label, run.stderr, want)
        runs.append({'backend': label, 'audited': audited, 'cases': len(arguments), 'passed': True, 'audit': run.stderr.strip()})
        print(label, 'audited' if audited else 'production', len(arguments), 'HTTP/SSE cases PASS', flush=True)

pending, visited = [ROOT / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
visited.update([Path(__file__).resolve(), ROOT / 'tests/channel_audit.py'])
compiler = Path(BEND).resolve().parent
record = {
    'scope': 'Injected affine HTTP event source through real callback/serial owner and SSE reader; exact IO traces and channel/parked-IO retirement. No real socket in this fixture; no universal concurrency claim.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/http-body-source-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-body-source-results.json').write_text(json.dumps(record, indent=2) + '\n')
