"""Character splitting with constant-depth recursive control, including long inputs."""
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(425)
rows = [(text, separator) for text in ['', ',', ',,', ',a,', '🙂x🙂', '\0a\0', 'a\ufeffb', 'éé'] for separator in [',', 'a', '🙂', '\0', 'é', '\ufeff']]
for _ in range(400):
    rows.append((''.join(rng.choice('x,🙂\0é\ufeff') for _ in range(rng.randrange(128))), rng.choice('x,🙂\0é\ufeff')))
args, expected = [], []
for text, separator in rows:
    args.append('s;' + ','.join(map(str, map(ord, text))) + ';' + str(ord(separator)))
    expected.append(''.join('+' + ','.join(map(str, map(ord, part))) + '/' for part in text.split(separator)))
for size in [0, 1, 4096, 16384, 65536, 131072]:
    for separator in [',', 'x']:
        args.append(f'g;{size};{ord(separator)}')
        expected.append(f'{size+1};0' if separator == 'x' else f'1;{size}')
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/string-split.bend', 'build/string-split'], cwd=ROOT, check=True)
subprocess.run([str(Path.home() / '.bend/bin/bend'), 'packages/runtime/test/string-split.bend', '-o', 'build/string-split.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/string-split', '--threads', '1']), ('native 4', ['build/string-split', '--threads', '4']), ('Bun', [str(Path.home() / '.bun/bin/bun'), 'build/string-split.js'])]:
    for start in range(0, len(args), 16):
        result = subprocess.run([*command, *args[start:start+16]], cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, start, result.stderr)
        assert result.stdout.splitlines() == expected[start:start+16], (label, start, result.stdout[:500])
    print(f'{label}: {len(args)} splits including 131072-character inputs PASS', flush=True)
