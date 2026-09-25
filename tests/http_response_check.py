"""Exact IO traces for affine response handoff, reads, and owner close.

Expected traces are declared by scenario; no Python response implementation is
used as the oracle. The separate progress laws quantify over payloads/errors.
"""
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys
from channel_audit import instrument

ROOT = Path(__file__).resolve().parents[1]
BEND = BEND
BUN = str(Path.home() / '.bun/bin/bun')
CALLBACKS = '--callbacks' in sys.argv
STEM = 'http-response-callbacks' if CALLBACKS else 'http-response'
SOURCE = f'packages/runtime/test/{STEM}.bend'
arguments, expected = [], []

def add(fails, actions, events, trace):
    arguments.append(';'.join([str(int(fails)), actions, *events]))
    expected.extend(['case', *trace])
    if CALLBACKS:
        expected.append(f'callbacks:{sum(line.startswith("read:") for line in trace)}:{trace.count("close")}')

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
        with (ROOT / f'build/{STEM}-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '8',
                            '--stats', f'build/{STEM}-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/{STEM}.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    f'build/{STEM}.c', '-lpthread', '-lm', '-o', f'build/{STEM}'], cwd=ROOT, check=True)

c = ROOT / f'build/{STEM}.c'
audit_c = ROOT / f'build/{STEM}-audit.c'
audit_c.write_text(c.read_text() + r"""
static void __attribute__((destructor)) callback_audit(void) {
  unsigned channels=0;
  for(u32 i=0;i<chan_len;i++) channels+=chan_rows[i].live;
  fprintf(stderr,"AUDIT %u %u 0\n",channels,io_park.head!=NULL);
}
""")
(ROOT / f'build/{STEM}-audit.js').write_text(instrument((ROOT / f'build/{STEM}.js').read_text()))
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1',str(audit_c),'-lpthread','-lm','-o',str(ROOT/f'build/{STEM}-audit')],check=True)
runs = []
for audited in [False, True]:
    suffix = '-audit' if audited else ''
    for label, command in [
        ('native-1', [str(ROOT / f'build/{STEM}{suffix}'), '--threads', '1']),
        ('native-4', [str(ROOT / f'build/{STEM}{suffix}'), '--threads', '4']),
        ('bun', [BUN, str(ROOT / f'build/{STEM}{suffix}.js')]),
    ]:
        run = subprocess.run(command + arguments, cwd=ROOT, text=True, capture_output=True, timeout=60, check=True)
        actual = run.stdout.splitlines()
        if actual != expected:
            for i, (observed, wanted) in enumerate(zip(actual, expected)):
                if observed != wanted:
                    raise AssertionError((label, i, actual[max(0, i-8):i+8], expected[max(0, i-8):i+8]))
            raise AssertionError((label, len(actual), len(expected)))
        assert run.stderr == ("AUDIT 0 0 0\n" if audited else ""), run.stderr
        runs.append({'backend': label, 'audited': audited, 'cases': len(arguments), 'trace_lines': len(expected), 'passed': True})
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
    'scope': 'Injected affine event source with real IO traces; validates handoff, exact read/close calls, error preservation and closed-cursor behavior. Native audits require zero live channels and parked IO; Bun audits channels, live IO and waiters. Does not exercise native sockets or prove scheduler liveness.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/{STEM}-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / f'build/{STEM}-results.json').write_text(json.dumps(record, indent=2) + '\n')
