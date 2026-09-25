"""OpenAI SDK error projection and actual pi error-body normalization oracle."""
import struct
import itertools
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys
from upstream_pin import PIN, UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
BEND = BEND
BUN = str(Path.home() / '.bun/bin/bun')
SOURCE = 'packages/ai/test/openai-http-error.bend'
arguments, expected = [], []
def scalars(text): return ','.join(str(ord(c)) for c in text)
def compact(value): return json.dumps(value,ensure_ascii=False,separators=(',',':'))
def add(status,provider,id,mode,raw,trace):
    arguments.extend([str(status),provider,id,mode,raw]);expected.extend(trace)

ordinary=[]
for status in range(400,600):
    ordinary.append(dict(status=status,provider='openai',id='-',raw='gateway blocked'))
values=[{'message':'blocked by gateway WAF'}, {'message':'Provider returned error','code':403,'metadata':{'raw':'upstream WAF blocked policy XYZ'}},
        {'message':'invalid','type':'invalid_request_error','code':'bad','param':None},
        {'message':'é🙂','code':42,'param':['x',1],'type':None},
        {'message':''},{'message':None},{'message':{'nested':['reason',1,True]}},
        {'message':3},{'detail':'reason'}, {}, [], ['reason'], 'reason', True, 3]
for status in [400,401,403,404,409,418,422,429,500,503]:
    for value in values:
        ordinary.append(dict(status=status,provider='openai',id='trace-42',raw=compact({'error':value})))
for provider in ['openai','openrouter','custom','']:
    for raw in ['', '  ', '<html>gateway blocked</html>', '{invalid', 'null', 'false', '0',
                'x'*4050, 'é🙂'+'x'*4048]:
        ordinary.append(dict(status=403,provider=provider,id='trace-42',raw=raw))
ordinary.append(dict(status=500,provider='openai',id='trace-long',raw=compact({'error':{'message':'x'*4050}})))
ordinary.append(dict(status=500,provider='openai',id='trace-long',raw=compact({'error':{'message':'🙂'*2020}})))
reference_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=UPSTREAM,text=True).strip()
assert reference_commit.startswith(PIN[:9])
def oracle(cases):
    return json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','tests/openai_http_error_reference.mts'],cwd=ROOT,input=json.dumps(cases),text=True))
reference=oracle(ordinary)
for case,trace in zip(ordinary,reference['results'],strict=True):
    add(case['status'],case['provider'],case['id'],'raw',case['raw'],trace)

# Approved native-value policy: diagnostics are not discarded by JS truthiness
# or solely because a gateway did not supply the SDK's error-envelope shape.
adaptations=[
 (compact({'error':{'message':'x'*3987+'🙂'}}),'500 '+'x'*3987+'🙂','{"message":"'+'x'*3987+'... [truncated 4 chars]'),
 ('{"message":"gateway"}','500 gateway','{"message":"gateway"}'),
 ('{"error":false}','500 false','500 false'),
 ('{"error":0}','500 0','500 0'),
 ('{"error":null}','500 null','500 null'),
 ('{"error":""}','500 ""','500 ""'),
 ('{"error":{"message":false}}','500 false','{"message":false}'),
 ('{"error":{"message":0}}','500 0','{"message":0}'),
 ('[1,2]','500 [1,2]','500 [1,2]'),
 ('"failure"','500 "failure"','500 "failure"'),
]
adaptation_reference=oracle([dict(status=500,provider='openai',id='-',raw=raw) for raw,_,_ in adaptations])
for (raw,message,rendered),original in zip(adaptations,adaptation_reference['results'],strict=True):
    trace=['case','kind:InternalServerError','status:500','request-id:none','code:none','param:none','type:none',
           'message:'+scalars(message),'format:'+scalars('OpenAI API error (500): '+rendered)]
    assert trace != original,(raw,'declared adaptation no longer differs')
    add(500,'openai','-','raw',raw,trace)
for status in [400,429,500]:
    add(status,'openai','-','read','',['case','read-limit:'+str(status)])
    add(status,'openai','-','encoding','unencoded',['case','encoding:'+str(status)+':'+scalars('unencoded')])

# Scalar-preserving truncation under a UTF-16 budget, including every boundary
# of short mixed-width strings. This oracle counts units without constructing
# surrogate characters.
for size in range(5):
    for chars in itertools.product(['a','é','🙂','𐀀'], repeat=size):
        text=''.join(chars)
        total=len(text.encode('utf-16-le'))//2
        for budget in range(total+2):
            kept=[]; used=0
            for char in text:
                width=len(char.encode('utf-16-le'))//2
                if used+width>budget: break
                kept.append(char);used+=width
            rendered=''.join(kept)
            if used<total: rendered+=f'... [truncated {total-used} chars]'
            add(budget,'openai','-','truncate',text,['case','truncated:'+scalars(rendered)])

for text,total,prefix in [('x'*100000,100000,'x'*4000),('🙂'*20000,40000,'🙂'*2000)]:
    add(4000,'openai','-','truncate',text,['case','truncated:'+scalars(prefix+f'... [truncated {total-4000} chars]')])

if '--no-build' not in sys.argv:
    for backend in ['c', 'js']:
        with (ROOT / f'build/openai-http-error-{backend}-build.log').open('w') as log:
            subprocess.run([sys.executable, 'scripts/run-rss-guarded.py', '--limit-gib', '12',
                            '--stats', f'build/openai-http-error-{backend}-build.json', '--',
                            BEND, SOURCE, '-o', f'build/openai-http-error.{backend}'],
                           cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1',
                    'build/openai-http-error.c', '-lpthread', '-lm', '-o', 'build/openai-http-error'], cwd=ROOT, check=True)

runs = []
for label, command in [
    ('native-1', [str(ROOT / 'build/openai-http-error'), '--threads', '1']),
    ('native-4', [str(ROOT / 'build/openai-http-error'), '--threads', '4']),
    ('bun', [BUN, str(ROOT / 'build/openai-http-error.js')]),
]:
    run = subprocess.run(command + arguments, cwd=ROOT, text=True, capture_output=True, timeout=60, check=True)
    actual = run.stdout.splitlines()
    if actual != expected:
        for i, (observed, wanted) in enumerate(zip(actual, expected)):
            if observed != wanted:
                raise AssertionError((label, i, actual[max(0, i-8):i+8], expected[max(0, i-8):i+8]))
        raise AssertionError((label, len(actual), len(expected)))
    assert not run.stderr, run.stderr
    runs.append({'backend': label, 'cases': len(arguments)//5, 'trace_lines': len(expected), 'passed': True})
    print(label, len(arguments)//5, 'OpenAI HTTP error traces PASS', flush=True)

pending, visited = [ROOT / SOURCE], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
visited.add(Path(__file__).resolve())
visited.add(ROOT / "tests/openai_http_error_reference.mts")
compiler = Path(BEND).resolve().parent
record = {
    'scope': 'Typed OpenAI HTTP error construction and shared pi normalization. Ordinary cases compare exact SDK fields/messages and actual pi formatting. Declared information-preservation adaptations compare explicit expectations and retain original SDK differences. No full provider stream or real HTTP request in this fixture.',
    'reference': reference,
    'adaptation_reference': adaptation_reference,
    'reference_commit': reference_commit,
    'runs': runs,
    'source_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'program_sha256': {suffix: hashlib.sha256((ROOT / ('build/openai-http-error' + suffix)).read_bytes()).hexdigest() for suffix in ['', '.c', '.js']},
    'compiler_command': BEND,
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']},
    'builds': {backend: json.loads((ROOT / f'build/openai-http-error-{backend}-build.json').read_text()) for backend in ['c', 'js']},
}
(ROOT / 'build/openai-http-error-results.json').write_text(json.dumps(record, indent=2) + '\n')
