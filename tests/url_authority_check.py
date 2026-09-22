"""Authority tokenization and credential escaping; host validity is a later stage."""
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
SAFE = "!$%&'()*+,-._~"
def credentials(text):
    username, separator, password = text.partition(':')
    return quote(username, safe=SAFE), quote(password if separator else '', safe=SAFE)

def tokens(text):
    userinfo, at, host_port = text.rpartition('@')
    if not at:
        host_port = text
    inside = False
    host, port = host_port, None
    for index, char in enumerate(host_port):
        if char == '[':
            inside = True
        elif char == ']':
            inside = False
        elif char == ':' and not inside:
            host, port = host_port[:index], host_port[index + 1:]
            break
    return credentials(userinfo) if at else None, host, port

def codes(text):
    return ','.join(map(str, map(ord, text)))

def expected(text):
    user, host, port = tokens(text)
    fields = ['absent', '', ''] if user is None else ['present', codes(user[0]), codes(user[1])]
    return ';'.join([*fields, codes(host), 'absent' if port is None else 'present', codes(port or '')])

texts = ['', '@', ':', ':80', '@:80', '@host', ':@host', 'a:b:c@host',
         'a@b:c@host', 'a:b@c@host', 'a@@host', 'a@', '[::1]', '[::1]:80',
         '[::1]:', '[::1', '[[::1]]:80', 'a[b:c]d:9', 'a]b:c', 'a[b:c',
         '[::1]garbage:80', 'a%40b:p%3Ass@example.com:443', '%@host',
         'user:pass@[::ffff:192.0.2.1]:8080']
# Token functions do not strip controls or interpret path delimiters. Those
# remain direct, independent token checks rather than URL constructor claims.
texts += [f'a{chr(code)}:b{chr(code)}@example.com:80' for code in range(256)]
texts += [f'a{char}:b{char}@example.com' for char in ['é', '🙂', '\ufeff', '\ufffd', '\u200c']]
rng = random.Random(20260922)
alphabet = 'abc012:@[]%+;=-é🙂 '
texts += [''.join(rng.choices(alphabet, k=rng.randrange(60))) for _ in range(1500)]
# Valid authority suffixes isolate credentials for actual URL comparisons.
for _ in range(1000):
    prefix = ''.join(rng.choices(alphabet, k=rng.randrange(40)))
    texts.append(prefix + '@' + rng.choice(['example.com', 'example.com:80', '[::1]', '[::1]:443', 'example.com:00021']))
for size in [1024, 8192]:
    texts += ['@' * size + 'example.com', 'a' * size + ':p@example.com:80',
              'u:' + ':' * size + '@[::1]:65535', '[' + '0' * size + ']:80']
reference = [expected(text) + ';' for text in texts]
# Compare the credential tuple against actual URL parsing. Restrict suffixes to
# canonical hosts and valid ports so lexical extraction is tested independently
# of IDNA/IPv4 parsing. Controls removed by URL preprocessing are excluded.
rows = []
for index, text in enumerate(texts):
    user, host, port = tokens(text)
    if host in ['example.com', '[::1]'] and (port is None or port.isascii() and port.isdecimal() and len(port) <= 5 and int(port) <= 65535):
        if not any(char in text for char in '\t\n\r/#?\\'):
            for scheme in ['http', 'https', 'custom']:
                rows.append([index, scheme, text])
script = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([i,scheme,text])=>{
 const u=new URL(scheme+'://'+text+'/');
 return [i,scheme,u.username,u.password,u.hostname,u.port];
})));
'''
actual = json.loads(subprocess.check_output(['node', '-e', script], input=json.dumps(rows), text=True))
for index, scheme, username, password, host, port in actual:
    user, raw_host, raw_port = tokens(texts[index])
    default = {'http': 80, 'https': 443}.get(scheme)
    want_port = '' if raw_port is None or int(raw_port) == default else str(int(raw_port))
    assert (username, password, host, port) == (*(user or ('', '')), raw_host, want_port), (index, scheme, texts[index])
print(f'Node authority cross-check: {len(actual)} cases PASS', flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-authority.bend', 'build/url-authority'], cwd=ROOT, check=True)
subprocess.run([str(Path(BEND)), 'packages/runtime/test/url-authority.bend', '-o', 'build/url-authority.js'], cwd=ROOT, check=True)
arguments = ['t;' + codes(text) for text in texts]
for special in [False, True]:
    for authority in ['', '@', 'a:b@example.com:80', 'a@b:c@[::1]:443', 'a\\b@host']:
        for suffix in ['', '/a@b:9?q#f', '?a@b:9#f', '#a@b:9', '\\a@b:9', '/🙂', '?', '#']:
            text = authority + suffix
            stop = next((i for i, char in enumerate(text) if char in '/?#' or special and char == '\\'), len(text))
            arguments.append(('s;' if special else 'n;') + codes(text))
            reference.append(expected(text[:stop]) + ';' + codes(text[stop:]))
            texts.append(text)
for label, command in [('native 1', ['build/url-authority', '--threads', '1']),
                       ('native 4', ['build/url-authority', '--threads', '4']),
                       ('Bun', [str(Path.home()/'.bun/bin/bun'), 'build/url-authority.js'])]:
    for start in range(0, len(arguments), 32):
        result = subprocess.run([*command, *arguments[start:start+32]], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), reference[start:start+32], strict=True)):
            assert got == want, (label, start+offset, texts[start+offset], got, want)
    print(f'{label}: {len(texts)} authority token cases PASS', flush=True)
