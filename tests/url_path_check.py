"""Hierarchical path-state parsing and UTF-8 query/fragment encoding."""
import json
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SPECIAL = {'ftp', 'file', 'http', 'https', 'ws', 'wss'}

def encode(text, kind):
    extra = {'path': ' "#<>?^`{}', 'query': ' "#<>',
             'special': ' "#<>\'', 'fragment': ' "<>`'}[kind]
    return ''.join(f'%{byte:02X}' if byte < 32 or byte > 126 or chr(byte) in extra else chr(byte)
                   for byte in text.encode('utf-8'))

def reference(scheme, base, text):
    path_query, fragment_mark, fragment = text.partition('#')
    path, query_mark, query = path_query.partition('?')
    parts = re.split(r'[/\\]', path) if scheme in SPECIAL else path.split('/')
    output = list(base)
    for index, part in enumerate(parts):
        dot = part.lower().replace('%2e', '.')
        if dot in ['.', '..']:
            if dot == '..' and output and not (scheme == 'file' and len(output) == 1 and re.fullmatch('[a-zA-Z]:', output[0])):
                output.pop()
            if index == len(parts) - 1:
                output.append('')
        else:
            encoded = encode(part, 'path')
            if scheme == 'file' and not output and re.fullmatch('[a-zA-Z][:|]', encoded):
                encoded = encoded[0] + ':'
            output.append(encoded)
    return ['/' + '/'.join(output), encode(query, 'special' if scheme in SPECIAL else 'query') if query_mark else None,
            encode(fragment, 'fragment') if fragment_mark else None]

schemes = ['http', 'https', 'file', 'custom', 'ws', 'ftp']
texts = ['', '.', '..', '%2e', '%2E%2e', '.%2E', '%2e.', '%252e', '...', './', '../',
         'a/../../b', 'a//b/..', 'a/./b/../', '/a', '//', 'a\\b\\..\\c', 'C|/../x',
         'C:/../../x', '1|/../x', '%43|/../x', 'c%3A/../x', 'a/C|/../x',
         '?', '#', '?#', '?a+b=%20#é🙂', 'a?\'"<>#\'"<>', 'a#b?c#d',
         'a%2Fb/%2e%2F../z', 'a b/^[]{}|`', '\\?q#f']
texts += [f'a{chr(code)}b?q{chr(code)}v#f{chr(code)}z' for code in range(256)]
texts += ['é/🙂?é+🙂#é🙂', '\ufeff/\ufffd?\ufeff#\ufffd']
rng = random.Random(20260923)
pieces = ['', '.', '..', '%2e', '%2E', '.%2e', '%2E%2e', '%252e', 'a', 'é🙂', 'C|', 'D:', '%gg', 'a b', '^', '\\']
texts += ['/'.join(rng.choices(pieces, k=rng.randrange(1, 16))) + rng.choice(['', '?', '#', '?a+b=%20', '?x#y', '#a?b']) for _ in range(1000)]
cases = [(scheme, [], text) for scheme in schemes for text in texts]
for scheme in schemes:
    for base in [['a', 'b'], ['C:'], ['C:', 'folder'], ['']]:
        cases += [(scheme, base, text) for text in texts[:33]]
for size in [1024, 8192]:
    for scheme in ['http', 'file', 'custom']:
        cases += [(scheme, [], text) for text in ['a/' * size + '..', 'a' * size + '?é#🙂', 'C:/' + '../' * size + 'x', '?'+ 'é' * size, '#'+ '🙂' * size]]
expected = [reference(*case) for case in cases]
# No input preprocessing is performed by this path-state component. Exclude
# controls stripped elsewhere in a full constructor and trailing C0/space.
eligible = [(index, scheme, base, text) for index, (scheme, base, text) in enumerate(cases)
            if not any(c in text for c in '\t\n\r') and not (text and ord(text[-1]) <= 32)]
script = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([i,scheme,base,text])=>{
 const u=new URL((scheme==='file'?'file:///':scheme+'://example.com/')+(base.length?base.join('/')+'/':'')+text);
 const beforeFragment=u.href.split('#')[0];
 return [i,[u.pathname,beforeFragment.includes('?')?u.search.slice(1):null,u.href.includes('#')?u.hash.slice(1):null]];
})));
'''
actual = json.loads(subprocess.check_output(['node', '-e', script], input=json.dumps(eligible), text=True))
for index, got in actual:
    assert got == expected[index], (index, cases[index], got, expected[index])
print(f'Node path-state cross-check: {len(actual)} cases PASS', flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-path.bend', 'build/url-path'], cwd=ROOT, check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'), 'packages/runtime/test/url-path.bend', '-o', 'build/url-path.js'], cwd=ROOT, check=True)
def codes(text): return ','.join(map(str, map(ord, text)))
def wire(values):
    path, query, fragment = values
    return ';'.join([codes(path), 'absent' if query is None else 'present', codes(query or ''), 'absent' if fragment is None else 'present', codes(fragment or '')])
arguments = [scheme+';'+('/'.join(base) if base else '-')+';'+codes(text) for scheme, base, text in cases]
# Actual post-authority remainders include the leading delimiter. These cases
# distinguish an absent non-special path from a special scheme's root path.
start_cases = [(scheme, text) for scheme in schemes for text in ['', '?', '#', '?a+b=é#🙂', '#a?b', '/', '/a/../b', '//a', '/.?', '/..#']]
start_cases += [(scheme, '\\a\\..\\b?x#y') for scheme in schemes if scheme in SPECIAL]
start_oracle = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([scheme,text])=>{
 const u=new URL((scheme==='file'?'file://':scheme+'://example.com')+text);
 return [u.pathname,u.href.split('#')[0].includes('?')?u.search.slice(1):null,u.href.includes('#')?u.hash.slice(1):null];
})));
'''
start_expected=json.loads(subprocess.check_output(['node','-e',start_oracle],input=json.dumps(start_cases),text=True))
for (scheme,text),result in zip(start_cases,start_expected,strict=True):
    cases.append((scheme, [], text))
    arguments.append('s;'+scheme+';'+codes(text))
    expected.append(result)
print(f'Node path-start cross-check: {len(start_cases)} cases', flush=True)
expected = list(map(wire, expected))
for label, command in [('native 1', ['build/url-path', '--threads', '1']),
                       ('native 4', ['build/url-path', '--threads', '4']),
                       ('Bun', [str(Path.home()/'.bun/bin/bun'), 'build/url-path.js'])]:
    start = 0
    while start < len(arguments):
        end, size = start, 0
        while end < len(arguments) and end-start < 64 and size+len(arguments[end]) < 262144:
            size += len(arguments[end]); end += 1
        assert end > start
        result = subprocess.run([*command, *arguments[start:end]], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:end], strict=True)):
            assert got == want, (label, start+offset, cases[start+offset], got[:500], want[:500])
        start = end
    print(f'{label}: {len(cases)} path-state cases PASS', flush=True)
