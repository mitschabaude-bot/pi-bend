"""IO contracts for provider status handling and retry metadata projection."""
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
SOURCE = 'packages/ai/test/provider-http-response.bend'
arguments, expected = [], []

def scalars(text):
    return ','.join(str(ord(c)) for c in text)

def add(code, limit, cleanup, consume, headers, events, trace):
    arguments.append(';'.join([str(code), str(limit), str(int(cleanup)), str(int(consume)), headers, *events]))
    fields = {}
    for field in headers.split('/'):
        if not field: continue
        key, value = field.split('=', 1)
        fields.setdefault(key, []).append(value)
    def joined(key):
        return ', '.join(fields[key]) if key in fields else None
    def optional(key):
        value = joined(key)
        return 'none' if value is None else 'some:' + scalars(value)
    should = joined('x-should-retry')
    retry = should == 'true' or (should != 'false' and (code in [408,409,429] or code >= 500))
    high, low = struct.unpack('>II', struct.pack('>d', code))
    projection = f'project:original:message:{high},{low}:' + ':'.join(optional(k) for k in ['x-should-retry','retry-after-ms','retry-after']) + ':' + ('retry' if retry else 'stop')
    expected.extend(['case', projection, *trace])

# Accept all and only successful statuses. Accepted responses do no body IO,
# even when the diagnostic limit is zero and an unread source would fail.
for code in range(100, 600):
    if 200 <= code < 300:
        add(code,0,False,False,'',['ebroken'],[f'accepted:{code}','close','closed:end'])
    else:
        add(code,10,False,False,'',['b65','cfin','eunread'],['read:b65','read:cfin','close',f'rejected:{code}:text:65'])

for headers in ['', 'x-should-retry=true', 'x-should-retry=false', 'x-should-retry=TRUE',
                'x-should-retry=true/x-should-retry=false',
                'retry-after-ms=25/retry-after=2', 'retry-after-ms=0',
                'retry-after-ms=2/retry-after-ms=3/retry-after=Wed, 21 Oct 2015 07:28:00 GMT']:
    for code in [200,400,408,409,429,500]:
        if code == 200:
            add(code,0,False,True,headers,['b65,66','cfin','eunread'],['accepted:200','read:b65,66','read:cfin','close','consumer:bytes:65,66'])
        else:
            add(code,4,False,False,headers,['cfin','eunread'],['read:cfin','close',f'rejected:{code}:text:'])

for cleanup in [False, True]:
    suffix = '+cleanup' if cleanup else ''
    add(200,0,cleanup,False,'',['ebroken'],['accepted:200','close','closed:error:cleanup' if cleanup else 'closed:end'])
    for limit,events,reads,result in [
        (0,['b65','eunread'],['b65'],'limit'+suffix),
        (2,['b65,66','b67','eunread'],['b65,66','b67'],'limit'+suffix),
        (10,['b65','ebroken','eunread'],['b65','ebroken'],'transport:broken'+suffix),
        (10,['b65'],['b65','eof'],'missing-completion'+suffix),
        (10,['h','eunread'],['h'],'unexpected'+suffix),
        (10,['b192,175','cfin'],['b192,175','cfin'],'cleanup' if cleanup else 'utf8:0:192'),
        (10,['b240,159','cfin'],['b240,159','cfin'],'cleanup' if cleanup else 'incomplete:2'),
    ]:
        add(429,limit,cleanup,False,'',events,['read:'+x for x in reads]+['close','rejected:429:error:'+result])
    add(500,1,cleanup,False,'',['b65','cfin'],['read:b65','read:cfin','close','rejected:500:'+('error:cleanup' if cleanup else 'text:65')])
for payload in [b'', b'\xef\xbb\xbf', 'é🙂'.encode()]:
    events=['b'+str(byte) for byte in payload]+['cfin','eunread']
    add(400,len(payload),False,False,'',events,['read:'+x for x in events[:-1]]+['close','rejected:400:text:'+scalars(payload.decode('utf-8-sig'))])

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        with (ROOT / f'build/provider-http-response-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '12',
                            '--stats', f'build/provider-http-response-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/provider-http-response.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    'build/provider-http-response.c', '-lpthread', '-lm', '-o', 'build/provider-http-response'], cwd=ROOT, check=True)

runs = []
for label, command in [
    ('native-1', [str(ROOT / 'build/provider-http-response'), '--threads', '1']),
    ('native-4', [str(ROOT / 'build/provider-http-response'), '--threads', '4']),
    ('bun', [BUN, str(ROOT / 'build/provider-http-response.js')]),
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
    print(label, len(arguments), 'provider status traces PASS', flush=True)

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
    'scope': 'Injected affine HTTP status boundary: all statuses 100..599, exact owner transfer/read/close traces, diagnostic limits and read/cleanup/UTF8 failures, retry metadata and header coalescing. No real sockets or complete SDK error normalization.',
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'program_sha256': {suffix: hashlib.sha256((ROOT / ('build/provider-http-response' + suffix)).read_bytes()).hexdigest() for suffix in ['', '.c', '.js']},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/provider-http-response-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/provider-http-response-results.json').write_text(json.dumps(record, indent=2) + '\n')
