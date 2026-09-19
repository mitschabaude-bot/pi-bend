"""Differential URL resolution, including every pinned base-dependent WPT row.

The fixture uses explicit strict Unicode options; these cases do not decide the
separately pending permissive-Node IDNA policy. No base-dependent row is skipped.
"""
import argparse
import json
from pathlib import Path
import random
import subprocess
import wpt_url_data as data

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--backend', choices=['js', 'native'], required=True)
parser.add_argument('--wpt-only', action='store_true', help='Run the pinned WPT subset; does not establish broader Node parity')
args = parser.parse_args()
rows = [(i, r) for i, r in data.rows() if r.get('base') is not None]
cases = [(data.scalar_value(r['input']), data.scalar_value(r['base'])) for _, r in rows]
bases = [
    'https://u:p@example.com:8443/a/b?old#hash', 'http://h/a/b',
    'ftp://h/a/', 'ws://h/', 'wss://h/a', 'custom:/a/b?old#hash',
    'custom://u:p@host:90/a/b?old#hash', 'custom:///', 'custom:/',
    'data:text,hello?old#hash', 'data:text,hello  ?old#hash',
    'file:///C:/a/b?old#hash', 'file://server/C:/a/b', 'file:///a/b',
    'file://server/a/b', 'file:///', 'https://[::1]/a', 'not a base',
]
references = [
    '', ' ', '\t\n', '#', '#new', '?', '?new', '?new#hash', '.', '..', './', '../',
    '../../x', '%2e/%2e%2e/x', 'a//b', '/', '//', '///', '////x',
    '\\', '\\\\', '/\\x/a', '\\/x/a', '/root', '//new:90/a', '//u:p@new/a',
    '//[::1]/x', '//localhost/a', 'x?y#z', 'x#y?z', 'é/🙂', ' x \t\r\n',
    'http:x', 'http:/x', 'http://x', 'https:x', 'https:/x', 'https://x',
    'custom:x', 'custom:/x', 'custom://x', 'file:x', 'file:/x', 'file://x/a',
    'C:/x', 'C|/x', 'C|', 'C|?x', 'C|#x', 'C|x', '/C:/x', '/C|/x',
    '//C:/x', '//C|/x', 'file:C|/x', 'file:/C|/x', '/..', '/?', '/#',
    'x:' + 'a' * 64, 'a' * 8192 + '/..',
]
cases.extend((reference, base) for base in bases for reference in references)
for base in bases[:2] + bases[5:7] + bases[11:15]:
    cases.extend(('a' + chr(code) + 'b?c#d', base) for code in range(128))
rng = random.Random(20260919)
parts = ['', '.', '..', '%2e', '%2e%2E', 'a', 'é', 'C|', 'C:', '?q', '#f', '/', '\\']
for _ in range(1000):
    cases.append((''.join(rng.choices(parts, k=rng.randrange(1, 8))), rng.choice(bases)))
if args.wpt_only:
    cases = cases[:len(rows)]
node = json.loads(subprocess.check_output(['node', '-e', r'''
const xs=JSON.parse(require('fs').readFileSync(0,'utf8'));
console.log(JSON.stringify({versions:process.versions,values:xs.map(([x,b])=>{try{return new URL(x,b).href}catch{return null}})}));
'''], input=json.dumps(cases), text=True))
def codes(text):
    return ','.join(map(str, map(ord, text)))
expected = ['invalid' if x is None else '+' + codes(x) for x in node['values']]
differences = [dict(index=i, input=r['input'], base=r['base'], wpt=r.get('href'), node=value)
               for (i, r), value in zip(rows, node['values'][:len(rows)], strict=True) if r.get('href') != value]
report = {'source': data.URL, 'sha256': data.SHA256, 'nodeVersions': node['versions'],
          'baseDependentInputs': len(rows), 'totalCases': len(cases), 'wptNodeDifferences': differences}
(ROOT / ('build/url-resolve-wpt-reference.json' if args.wpt_only else 'build/url-resolve-reference.json')).write_text(json.dumps(report, indent=2, ensure_ascii=True) + '\n')
backends = [('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/url-resolve.js'])] if args.backend == 'js' else [
    ('native 1', ['build/url-resolve', '--threads', '1']), ('native 4', ['build/url-resolve', '--threads', '4'])]
print(f'{len(cases)} cases including all {len(rows)} base-dependent WPT rows; {len(differences)} WPT/Node differences', flush=True)
failures = []
for label, command in backends:
    for start in range(0, len(cases), 16):
        batch = cases[start:start+16]
        values = [codes(value) for pair in batch for value in pair]
        result = subprocess.run([*command, *values], cwd=ROOT, capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+16], strict=True)):
            if got != want:
                failures.append(dict(backend=label, index=start+offset, input=cases[start+offset][0], base=cases[start+offset][1], got=got, expected=want))
    print(f'{label}: {len(cases)} URL resolutions checked', flush=True)
(ROOT / ('build/url-resolve-wpt-failures.json' if args.wpt_only else 'build/url-resolve-failures.json')).write_text(json.dumps(failures, indent=2) + '\n')
assert not failures, f'{len(failures)} mismatches; see build/url-resolve-failures.json'
print('All resolutions match Node PASS', flush=True)
