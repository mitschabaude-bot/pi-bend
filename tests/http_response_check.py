"""Exact IO traces for affine response handoff, reads, and owner close.

Expected traces are declared by scenario; no Python response implementation is
used as the oracle. The separate progress laws quantify over payloads/errors.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(ROOT / 'build/bend-profiles/dns-transport-teles/bend2/main.ts'))
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'packages/runtime/test/http-response.bend'
arguments, expected = [], []

def add(fails, actions, events, trace):
    arguments.append(';'.join([str(int(fails)), actions, *events]))
    expected.extend(['case', *trace])

for fails in [False, True]:
    cleanup = 'error:cleanup' if fails else 'end'
    suffix = '+cleanup' if fails else ''
    add(fails, 'nnnc', ['i', 'i', 'h', 'b65,66', 'b67', 'cfin', 'eunread'], [
        'read:i', 'read:i', 'read:h', 'head:200:body',
        'read:b65,66', 'bytes:65,66', 'read:b67', 'bytes:67',
        'read:cfin', 'close', cleanup, 'end', 'final:end:fin'])
    add(fails, 'nn', ['h', 'b', 'b', 'b0,255', 'cfin'], [
        'read:h', 'head:200:body', 'read:b', 'read:b', 'read:b0,255',
        'bytes:0,255', 'read:cfin', 'close', cleanup, 'final:end:fin'])
    add(fails, 'nnc', ['z', 'b65,66', 'b67', 'cfin', 'eunread'], [
        'read:z', 'head:200:null', 'read:b65,66', 'read:b67',
        'read:cfin', 'close', cleanup, 'end', 'end', 'final:end:fin'])
    for exposed in ['h', 'z']:
        heading = 'head:200:' + ('body' if exposed == 'h' else 'null')
        add(fails, 'cnc', [exposed, 'eunread'], [
            'read:' + exposed, heading, 'close', cleanup, 'end', 'end', 'final:end:none'])
        add(fails, '', [exposed, 'eunread'], [
            'read:' + exposed, 'head', 'close', 'final:' + cleanup + ':none'])
        for event, primary in [('ebroken', 'transport:broken'), ('h', 'unexpected'), ('i', 'unexpected')]:
            add(fails, 'nnc', [exposed, event, 'eunread'], [
                'read:' + exposed, heading, 'read:' + event, 'close',
                'error:' + primary + suffix, 'end', 'end', 'final:end:none'])
        add(fails, 'nn', [exposed], [
            'read:' + exposed, heading, 'read:eof', 'close',
            'error:missing-completion' + suffix, 'end', 'final:end:none'])
    for event, primary in [('ebroken', 'transport:broken'), ('b65', 'unexpected'), ('cfin', 'unexpected')]:
        add(fails, 'n', ['i', event, 'eunread'], [
            'read:i', 'read:' + event, 'close', 'start-error:' + primary + suffix])
    add(fails, 'n', ['i'], ['read:i', 'read:eof', 'close', 'start-error:missing-head' + suffix])

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        with (ROOT / f'build/http-response-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                            '--stats', f'build/http-response-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/http-response.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    'build/http-response.c', '-lpthread', '-lm', '-o', 'build/http-response'], cwd=ROOT, check=True)

runs = []
for label, command in [
    ('native-1', [str(ROOT / 'build/http-response'), '--threads', '1']),
    ('native-4', [str(ROOT / 'build/http-response'), '--threads', '4']),
    ('bun', [BUN, str(ROOT / 'build/http-response.js')]),
]:
    run = subprocess.run(command + arguments, cwd=ROOT, text=True, capture_output=True, timeout=60, check=True)
    actual = run.stdout.splitlines()
    if actual != expected:
        for i, (observed, wanted) in enumerate(zip(actual, expected)):
            if observed != wanted:
                raise AssertionError((label, i, actual[max(0, i-8):i+8], expected[max(0, i-8):i+8]))
        raise AssertionError((label, len(actual), len(expected)))
    assert not run.stderr, run.stderr
    runs.append({'backend': label, 'cases': len(arguments), 'trace_lines': len(expected), 'passed': True})
    print(label, len(arguments), 'response ownership traces PASS', flush=True)

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
    'scope': 'Injected affine event source with real IO traces; validates handoff, exact read/close calls, error preservation and closed-cursor behavior. Does not exercise native sockets or prove scheduler/resource retirement.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/http-response-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-response-results.json').write_text(json.dumps(record, indent=2) + '\n')
