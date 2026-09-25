"""Unicode 17 NFC/NFD conformance, with an independent Node/ICU cross-check."""
import importlib.util
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('unicode_data', ROOT / 'scripts/generate-unicode-normalization.py')
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
subprocess.run([sys.executable, 'scripts/generate-unicode-normalization.py', '--check'], cwd=ROOT, check=True)
cases = {}
part = ''
listed = set()
rows = 0

def add(form, source, expected):
    key = (form, tuple(source))
    value = tuple(expected)
    if key in cases:
        assert cases[key] == value
    cases[key] = value

for line in data.source('NormalizationTest.txt').splitlines():
    if line.startswith('@'):
        part = line.split()[0]
    line = line.split('#')[0].strip()
    if not line or line.startswith('@'):
        continue
    columns = [tuple(int(value, 16) for value in field.split()) for field in line.split(';')[:5]]
    c1, c2, c3, c4, c5 = columns
    rows += 1
    if part == '@Part1':
        listed.update(c1)
    for column in columns[:3]:
        add('c', column, c2)
        add('d', column, c3)
    for column in columns[3:]:
        add('c', column, c4)
        add('d', column, c5)
add('c', [], [])
add('d', [], [])
# Unicode's character-by-character stability invariant for all other scalars.
# NUL separators prevent composition/reordering between independent characters.
batch = []
unlisted = 0
for code in range(0x110000):
    if code in listed or 0xD800 <= code <= 0xDFFF:
        continue
    batch.extend([code, 0])
    unlisted += 1
    if len(batch) == 1024:
        for form in ['c', 'd']:
            add(form, batch, batch)
        batch = []
if batch:
    for form in ['c', 'd']:
        add(form, batch, batch)
items = list(cases.items())
oracle = r'''
const rows=JSON.parse(require('fs').readFileSync(0,'utf8'));
if(process.versions.unicode!=='17.0')throw Error('Unicode version mismatch: '+process.versions.unicode);
for(const [[form,points],expected] of rows){
 const got=[...String.fromCodePoint(...points).normalize(form==='c'?'NFC':'NFD')].map(c=>c.codePointAt(0));
 if(JSON.stringify(got)!==JSON.stringify(expected))throw Error(JSON.stringify({form,points,got,expected}));
}
'''
subprocess.run(['node', '-e', oracle], input=json.dumps(items), text=True, check=True)
print(f'{rows} Unicode conformance rows, {unlisted} unlisted scalars: Node/ICU agrees', flush=True)
arguments = [form + ';' + ','.join(map(str, points)) for (form, points), _ in items]
expected = [','.join(map(str, value)) for _, value in items]
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/runtime/test/unicode-normalization.bend', 'build/unicode-normalization'], cwd=ROOT, check=True)
subprocess.run([str(Path(BEND)), 'packages/runtime/test/unicode-normalization.bend', '-o', 'build/unicode-normalization.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/unicode-normalization', '--threads', '1']), ('native 4', ['build/unicode-normalization', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/unicode-normalization.js'])]:
    for start in range(0, len(arguments), 128):
        result = subprocess.run([*command, *arguments[start:start+128]], cwd=ROOT, text=True, capture_output=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+128], strict=True)):
            assert got == want, (label, start+offset, arguments[start+offset][:180], got[:300], want[:300])
    print(f'{label}: {len(items)} NFC/NFD comparisons PASS', flush=True)

# Reuse this build for long combining-run checks.
subprocess.run([sys.executable, "tests/unicode_normalization_growth.py", "--no-build"], cwd=ROOT, check=True)
