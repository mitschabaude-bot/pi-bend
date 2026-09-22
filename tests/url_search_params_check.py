"""Immutable URL query/form behavior against actual Node URLSearchParams."""
import json
import os
import hashlib
import re
from pathlib import Path
from bend_toolchain import BEND
import random
import subprocess
import sys
from urllib.parse import unquote_to_bytes, quote_plus

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(917)
rows = []

def codes(text):
    # Bend strings contain Unicode scalars. URLSearchParams applies this same
    # USVString conversion to JS inputs before parsing or mutation.
    text = text.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'replace')
    return ','.join(str(ord(char)) for char in text)

def add(kind, **kwargs):
    rows.append(dict(kind=kind, **kwargs))

queries = ['x=%FFé🙂', 'x=%éF🙂', '', '?', '??', '&', '&&', 'a', '=','==', 'a=b=c', 'a=1&a=2&b=&=x', '?a=1', 'a+b=c+d', 'x=%2B+%20', 'x=%2520', 'x=%', 'x=%2', 'x=%gg', 'x=%%32', 'x=%2%32', '%26=%3D', '\ufeff=x', 'x=%EF%BB%BF', 'x=%EF%BB%BF%EF%BB%BF', 'x=%FF%EF%BB%BF', '?emoji=🙂', 'x=\ud800', 'x=\udc00', 'x=\ud83d\ude42', 'x=\x00\r\n', 'x=%C0%AF', 'x=%E0%80%80', 'x=%ED%A0%80', 'x=%F4%90%80%80']
queries += ['x=' + ''.join('%' + f'{byte:02X}' for byte in data) for data in [[n] for n in range(256)] + [[n, 0x80] for n in range(0xC0, 0x100)] + [[0xE2, 0x82], [0xF0, 0x9F, 0x99], [0xE2, 65, 0xA1]]]
alphabet = 'ab+=&?%012AFgzé🙂\ufeff\ud800\udc00'
queries += [''.join(rng.choice(alphabet) for _ in range(rng.randrange(40))) for _ in range(120)]
for query in queries:
    add('p', text=query)
    add('f', text=query)
values = ['', 'a b+c', '!~*()\'_-./', '\ufeff', 'é🙂', '\ud800', '\udc00', '\ud83d\ude42', '\x00\r\n', 'a\ud800b\udc00']
for name in values:
    for value in values:
        add('n', name=name, value=value)
for initial in ['b=0&a=1&b=2&a=3', '=zero&&x=&=last', '😀=0&\uffff=1&𐀀=2&😀=3', '?code=x&state=a+b']:
    ops = [('g', 'a', None), ('l', 'a', None), ('h', 'x', None), ('h', 'x', ''), ('a', 'a', '4'), ('s', 'a', '5'), ('a', 'a', '6'), ('d', 'a', '5'), ('r', '', None), ('d', 'a', None), ('s', 'absent', 'new'), ('g', 'missing', None)]
    add('q', text=initial, ops=ops)
for _ in range(80):
    ops = []
    for step in range(24):
        kind = rng.choice(['a', 's', 'd', 'r', 'g', 'l', 'h', 'k', 'v'])
        ops.append((kind, rng.choice(values), rng.choice(values + [None]) if kind in ['d', 'h'] else rng.choice(values)))
    add('q', text=rng.choice(queries), ops=ops)
# Exercise stable merge ordering and duplicate handling beyond tiny OAuth forms.
add('q', text='&'.join(f'key{i % 31}={i}' for i in range(1024)), ops=[('r', '', None), ('s', 'key4', 'replace'), ('d', 'key9', None)])

NODE = r'''
const rows = JSON.parse(await new Response(process.stdin).text());
const text = s => [...s].map(c=>c.codePointAt(0)).join(',');
const entries = q => [...q].map(([k,v])=>text(k)+':'+text(v)+'/').join('');
const show = q => q.toString()+'~'+entries(q)+'~'+q.size;
// The standard parses UTF-8 bytes. Node's malformed-percent fallback can
// truncate literal non-ASCII UTF-16 units. Encode only non-ASCII input before
// Node parsing, preserving delimiters, existing escapes and the leading '?'.
const input = s => process.env.FORM_RAW_ORACLE ? s : s.toWellFormed().replace(/[^\x00-\x7f]/gu, c => encodeURIComponent(c));
const results = rows.map(row => {
 if (row.kind === 'p') return show(new URLSearchParams(input(row.text)));
 if (row.kind === 'f') return entries(new URLSearchParams('?'+input(row.text)));
 if (row.kind === 'n') return show(new URLSearchParams([[row.name,row.value]]));
 const q = new URLSearchParams(input(row.text)); const trace = [show(q)];
 for (const [op,name,value] of row.ops) {
   const before = show(q);
   if (op==='k' || op==='v') trace.push([...(op==='k'?q.keys():q.values())].map(v=>'+'+text(v)+'/').join(''));
   else if (op==='g') { const value=q.get(name);trace.push(value===null?'-':'+'+text(value)); }
   else if (op==='l') trace.push(q.getAll(name).map(v=>'+'+text(v)+'/').join(''));
   else if (op==='h') trace.push((value===null?q.has(name):q.has(name,value))?'yes':'no');
   else {
     if (op==='a')q.append(name,value);
     if (op==='s')q.set(name,value);
     if (op==='d') { if(value===null)q.delete(name);else q.delete(name,value); }
     if (op==='r')q.sort();
     trace.push(before+'>'+show(q));
   }
 }
 return trace.join('#');
});
console.log(JSON.stringify(results));
'''
expected = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', NODE], input=json.dumps(rows), text=True))
raw = json.loads(subprocess.check_output(['node', '--input-type=module', '-e', NODE], input=json.dumps(rows), text=True, env={**os.environ, 'FORM_RAW_ORACLE': '1'}))
oracle_differences = [dict(index=i, case=rows[i], raw_node=a, utf8_byte_input=b) for i, (a,b) in enumerate(zip(raw, expected, strict=True)) if a != b]
# Independently check the parsing oracle against the standard's byte algorithm.
# This does not implement production behavior or derive expectations from Bend.
def scalar(text):
    return text.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'replace')

def byte_parse(text):
    fields = scalar(text).encode('utf-8').split(b'&')
    result = []
    for field in fields:
        if not field:
            continue
        name, _, value = field.partition(b'=')
        result.append(tuple(unquote_to_bytes(part.replace(b'+', b' ')).decode('utf-8', 'replace') for part in (name, value)))
    return result

def encoded(text):
    return quote_plus(text, safe='*-._').replace('~', '%7E')

parser_checks = 0
for index, row in enumerate(rows):
    if row['kind'] not in ('p', 'f'):
        continue
    source = scalar(row['text'])
    if row['kind'] == 'p' and source.startswith('?'):
        source = source[1:]
    tuples = byte_parse(source)
    shown = ''.join(codes(k)+':'+codes(v)+'/' for k,v in tuples)
    if row['kind'] == 'p':
        shown = '&'.join(encoded(k)+'='+encoded(v) for k,v in tuples)+'~'+shown+'~'+str(len(tuples))
    assert shown == expected[index], (index, row, shown, expected[index])
    parser_checks += 1
arguments = []
for row in rows:
    if row['kind'] in ['p', 'f']:
        arguments.append(row['kind'] + ';' + codes(row['text']))
    elif row['kind'] == 'n':
        arguments.append('n;' + codes(row['name']) + ';' + codes(row['value']))
    else:
        ops = []
        for op, name, value in row['ops']:
            if op in ['r', 'k', 'v']:
                ops.append(op)
            elif op in ['g', 'l']:
                ops.append(op + ':' + codes(name))
            else:
                last = ('-' if value is None else '+' + codes(value)) if op in ['d', 'h'] else codes(value)
                ops.append(op + ':' + codes(name) + ':' + last)
        arguments.append('q;' + codes(row['text']) + ';' + '|'.join(ops))

if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-search-params.bend', 'build/url-search-params'], cwd=ROOT, check=True)
if '--no-build' not in sys.argv:
    subprocess.run([BEND, 'packages/runtime/test/url-search-params.bend', '-o', 'build/url-search-params.js'], cwd=ROOT, check=True)
differences = []
for label, command in [('native 1', ['build/url-search-params', '--threads', '1']), ('native 4', ['build/url-search-params', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/url-search-params.js'])]:
    for start in range(0, len(arguments), 16):
        result = subprocess.run([*command, *arguments[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        actual = result.stdout.splitlines()
        for offset, (got, want) in enumerate(zip(actual, expected[start:start+16], strict=True)):
            if got != want:
                if '--investigate' not in sys.argv:
                    raise AssertionError((label, start+offset, arguments[start+offset][:500], got[:1000], want[:1000]))
                differences.append(dict(backend=label, index=start+offset, argument=arguments[start+offset], bend=got, reference=want))
    count = sum(row['backend'] == label for row in differences)
    (ROOT / 'build/url-search-params-differences.json').write_text(json.dumps(differences, ensure_ascii=True, indent=2) + '\n')
    print(f'{label}: {len(arguments)} form/query cases, {len(rows)} actual URLSearchParams comparisons; {count} differences', flush=True)

if differences:
    output = ROOT / 'build/url-search-params-differences.json'
    output.write_text(json.dumps(differences, ensure_ascii=True, indent=2) + '\n')
    raise AssertionError(f'{len(differences)} backend differences retained in {output}')

def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
pending = [ROOT / 'packages/runtime/test/url-search-params.bend']
closure = set()
while pending:
    path = pending.pop().resolve()
    if path in closure:
        continue
    path.relative_to(ROOT)
    closure.add(path)
    pending.extend(path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE))
source_hashes = {str(path.relative_to(ROOT)): digest(str(path.relative_to(ROOT))) for path in sorted(closure)}
report = dict(source_closure_sha256=source_hashes, independent_byte_parser_checks=parser_checks, cases=len(rows), backends=['native 1', 'native 4', 'Bun'], comparisons=3*len(rows), oracle='Node URLSearchParams with literal non-ASCII converted to UTF-8 percent bytes', node_version=subprocess.check_output(['node','--version'], text=True).strip(), raw_node_differences=oracle_differences, differences=differences, sha256={p:digest(p) for p in ['packages/runtime/src/url.bend','packages/runtime/src/url.bend','packages/runtime/test/url-search-params.bend','tests/url_search_params_check.py','build/url-search-params','build/url-search-params.js']})
(ROOT / 'build/url-search-params-results.json').write_text(json.dumps(report, ensure_ascii=True, indent=2)+'\n')
print(f'{len(oracle_differences)} raw Node discrepancies retained independently')
