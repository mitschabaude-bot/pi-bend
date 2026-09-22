"""Exact IO traces for affine response handoff, reads, and owner close.

Expected traces are declared by scenario; no Python response implementation is
used as the oracle. The separate progress laws quantify over payloads/errors.
"""
import struct
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BEND = BEND
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'packages/runtime/test/http-body-consume.bend'
arguments, expected = [], []
def add(fails, mode, limit, events, trace):
    arguments.append(';'.join([str(int(fails)), mode, str(limit), *events]))
    expected.extend(['case', *trace])

def scalars(text):
    return ','.join(str(ord(c)) for c in text)

def shown(value):
    if value is None: return 'null'
    if isinstance(value, bool): return str(value).lower()
    if isinstance(value, (int, float)):
        high, low = struct.unpack('>II', struct.pack('>d', value))
        return f'n{high},{low}'
    if isinstance(value, str): return 's'+scalars(value)
    if isinstance(value, list): return '['+''.join(shown(x)+';' for x in value)+']'
    return '{'+''.join(scalars(k)+'='+shown(v)+';' for k,v in value.items())+'}'

def body(chunks):
    return ['b'+','.join(map(str, chunk)) for chunk in chunks]

def valid(mode, payload, chunks, spare=0):
    events = ['h', *body(chunks), 'cfin', 'eunread']
    text = payload.decode('utf-8-sig') if mode != 'bytes' else ''
    output = ('bytes:'+','.join(map(str,payload)) if mode == 'bytes' else
              'text:'+scalars(text) if mode == 'text' else 'json:'+shown(json.loads(text)))
    add(False, mode, len(payload)+spare, events, ['read:'+x for x in events[:-1]]+['close',output])

# Every partition of a short Unicode payload, plus empty chunks.
payload = 'Aé🙂'.encode()
for mask in range(1 << (len(payload)-1)):
    cuts=[0]+[i for i in range(1,len(payload)) if mask & (1 << (i-1))]+[len(payload)]
    chunks=[payload[a:b] for a,b in zip(cuts,cuts[1:])]
    valid('bytes',payload,[b'',*chunks,b''])
    valid('text',payload,chunks,spare=3)
for payload in [b'', b'\xef\xbb\xbf', b'\xef\xbb\xbf\xef\xbb\xbfA', b'a\x00b']:
    valid('text',payload,[bytes([b]) for b in payload])
for value in [None, True, 1.5, -0.0, 'é🙂', [True, None, 'x'], {'x':[None,True,1.5,-0.0,'é🙂']}]:
    payload=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
    valid('json',payload,[bytes([b]) for b in payload])
    bom=b'\xef\xbb\xbf'+payload
    valid('json',bom,[bom])
for fails in [False,True]:
    suffix='+cleanup' if fails else ''
    for mode in ['bytes','text','json']:
        add(fails,mode,0,['h','b65','eunread'],['read:h','read:b65','close','error:limit'+suffix])
        add(fails,mode,2,['h','b65,66','b67','eunread'],['read:h','read:b65,66','read:b67','close','error:limit'+suffix])
        for event,cause in [('ebroken','transport:broken'),('i','unexpected'),('h','unexpected')]:
            add(fails,mode,20,['h','b65',event,'eunread'],['read:h','read:b65','read:'+event,'close','error:'+cause+suffix])
        add(fails,mode,20,['h','b65'],['read:h','read:b65','read:eof','close','error:missing-completion'+suffix])
    for mode,output in [('bytes','bytes:'),('text','text:'),('json','error:json')]:
        add(fails,mode,0,['z','b65,66','cfin','eunread'],['read:z','read:b65,66','read:cfin','close','error:cleanup' if fails else output])
    add(fails,'bytes',1,['h','b65','cfin'],['read:h','read:b65','read:cfin','close','error:cleanup' if fails else 'bytes:65'])
# Decode failures occur after the single body close. Cleanup failure takes precedence.
for raw,cause in [([0xc0,0xaf],'utf8:0:192'),([0xe2,0x28],'utf8:1:40'),([0xf0,0x9f],'incomplete:2'),([256],'byte:0:256')]:
    for fails in [False,True]:
        events=['h',*body([raw]),'cfin']
        add(fails,'text',20,events,['read:'+x for x in events]+['close','error:cleanup' if fails else 'error:'+cause])
for payload in [b'',b'[1,]',b'{',b'true false']:
    events=['h',*body([payload]),'cfin']
    add(False,'json',20,events,['read:'+x for x in events]+['close','error:json'])

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        with (ROOT / f'build/http-body-consume-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '12',
                            '--stats', f'build/http-body-consume-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/http-body-consume.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    'build/http-body-consume.c', '-lpthread', '-lm', '-o', 'build/http-body-consume'], cwd=ROOT, check=True)

runs = []
for label, command in [
    ('native-1', [str(ROOT / 'build/http-body-consume'), '--threads', '1']),
    ('native-4', [str(ROOT / 'build/http-body-consume'), '--threads', '4']),
    ('bun', [BUN, str(ROOT / 'build/http-body-consume.js')]),
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
    print(label, len(arguments), 'buffered body traces PASS', flush=True)

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
    'scope': 'Owned buffered bytes/text/JSON with injected affine source and exact read/close traces. Every partition of short Unicode payload, byte limits and early stop, null-body suppression, transport/cleanup failures and strict UTF8/JSON decoding. Python standard codecs supply successful decode projections; error/ownership traces are specified directly. No real sockets or universal scheduler proof.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/http-body-consume-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/http-body-consume-results.json').write_text(json.dumps(record, indent=2) + '\n')
