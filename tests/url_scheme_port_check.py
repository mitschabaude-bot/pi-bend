"""Scheme tokens and delimited ports, independently checked against Node URLs."""
import json
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCHEMES = ['ftp', 'http', 'https', 'ws', 'wss', 'custom', 'HTTP', 'x+y.z-1']
DEFAULTS = {'ftp': 21, 'http': 80, 'https': 443, 'ws': 80, 'wss': 443}
cases = [(SCHEMES[value % len(SCHEMES)], str(value)) for value in range(65537)]
ports = ['', '0', '00', '21', '80', '443', '65535', '65536', '00080', '000443',
         '4294967295', '4294967296', '-1', '+1', '1a', '0x50', '1.5', '１２',
         '80 ', '80\t', '8\n0', '80/90', '80?x', '80#x', '80:90', '80\\x', '\0',
         '9' * 512, '9' * 512 + 'x', '0' * 8192 + '80']
for scheme in [*SCHEMES, 'file', 'FILE', 'a', 'mailto', 'HtTpS']:
    cases.extend((scheme, port) for port in ports)
for code in range(256):
    cases.extend([(chr(code) + 'x', ''), ('x' + chr(code), ''), ('http', '8' + chr(code))])
cases.extend((scheme, '') for scheme in ['', '1http', '+http', '.http', '-http',
              'é', '🙂', 'http:', 'https/', 'HTTP ', 'x' + 'A' * 8192])
rng = random.Random(20260921)
for _ in range(500):
    cases.append((rng.choice(SCHEMES), ''.join(rng.choices('0123456789ax+- ', k=rng.randrange(30)))))

def expected(scheme, port):
    if not re.fullmatch('[A-Za-z][A-Za-z0-9+.-]*', scheme):
        return 'invalid'
    scheme = scheme.lower()
    default = DEFAULTS.get(scheme)
    if port and not re.fullmatch('[0-9]+', port):
        value = 'digit'
    elif not port:
        value = '-'
    else:
        # Strip zeros before conversion to keep Python's huge-integer limit out
        # of the oracle; decimal magnitude is independently bounded.
        significant = port.lstrip('0') or '0'
        number = int(significant) if len(significant) <= 5 else 65536
        value = 'range' if number > 65535 else '-' if number == default else str(number)
    return ';'.join([scheme, 'special' if scheme in {*DEFAULTS, 'file'} else 'other',
                     str(default) if default is not None else '-', value])

reference = [expected(*case) for case in cases]
# Constructor preprocessing/delimiters and file's no-port authority rules are
# outside these token functions. Compare every case that reaches the same token
# boundary in a full URL; check other token cases with the independent oracle.
eligible = [(i, scheme, port) for i, (scheme, port) in enumerate(cases)
            if re.fullmatch('[A-Za-z][A-Za-z0-9+.-]*', scheme)
            and scheme.lower() != 'file'
            and not any(c in port for c in '\0\t\n\r /?#\\:')]
script = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify(rows.map(([i,scheme,port])=>{
 try {const u=new URL(scheme+'://example.com:'+port+'/'); return [i,u.protocol.slice(0,-1),u.port||'-'];}
 catch {return [i,null,null];}
})));
'''
actual = json.loads(subprocess.check_output(['node', '-e', script], input=json.dumps(eligible), text=True))
for index, scheme, port in actual:
    want = reference[index].split(';')
    if want[-1] in ['digit', 'range']:
        assert scheme is None, (cases[index], want, scheme, port)
    else:
        assert (scheme, port) == (want[0], want[-1]), (cases[index], want, scheme, port)
print(f'Node constructor cross-check: {len(eligible)} cases PASS', flush=True)
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/url-scheme-port.bend', 'build/url-scheme-port'], cwd=ROOT, check=True)
subprocess.run([str(Path.home()/'.bend/bin/bend'), 'packages/runtime/test/url-scheme-port.bend', '-o', 'build/url-scheme-port.js'], cwd=ROOT, check=True)
def codes(text):
    return ','.join(str(ord(c)) for c in text)
arguments = [codes(scheme) + ';' + codes(port) for scheme, port in cases]
for label, command in [('native 1', ['build/url-scheme-port', '--threads', '1']),
                       ('native 4', ['build/url-scheme-port', '--threads', '4']),
                       ('Bun', [str(Path.home()/'.bun/bin/bun'), 'build/url-scheme-port.js'])]:
    start = 0
    while start < len(arguments):
        end, size = start, 0
        while end < len(arguments) and end - start < 512 and size + len(arguments[end]) < 262144:
            size += len(arguments[end])
            end += 1
        assert end > start
        result = subprocess.run([*command, *arguments[start:end]], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), reference[start:end], strict=True)):
            assert got == want, (label, start + offset, cases[start + offset], got, want)
        start = end
    print(f'{label}: {len(cases)} scheme/port cases PASS', flush=True)
