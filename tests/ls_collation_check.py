"""Default ls ordering against Node 24 (pi's runtime): entries in readdir
order (byte order under Node) sorted by a.toLowerCase().localeCompare(b.toLowerCase()),
with a '/' suffix for directories."""
import argparse, base64, json, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = ['b', 'A', 'a', 'B', '_x', 'é', 'e', 'Z', '10', '9', 'ä', '.hidden', 'Apple', 'apple', 'APPLE', 'file10.txt', 'file9.txt', 'Ω', 'ω', 'straße', 'STRASSE', 'ﬁle', 'Éclair', 'eclair', '日本', 'zz-top', 'Zz', 'z_z', 'a.b', 'a-b', 'a b', '#x', '~tmp', 'Émile', 'emile', 'Σίσυφος', 'σίσυφοσ']
DIRS = ['Dir', 'dir2', 'ädir']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prefix', default=str(ROOT / 'build/ls-public'))
    parser.add_argument('backends', nargs='*', default=['bun'])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ls-collation-') as folder:
        root = Path(folder)
        for name in NAMES: (root / name).write_text('x')
        for name in DIRS: (root / name).mkdir()
        expected = subprocess.check_output(['node', '-e', '''
const fs = require("fs"), path = require("path");
const dir = process.argv[1];
const names = fs.readdirSync(dir);
names.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
console.log(JSON.stringify(names.map(n => fs.statSync(path.join(dir, n)).isDirectory() ? n + "/" : n).join("\\n")));
''', str(root)], text=True).strip()
        expected = json.loads(expected)
        for backend in args.backends:
            command = ['bun', args.prefix + '.js'] if backend == 'bun' else [args.prefix, '--threads', backend[-1], '--']
            result = subprocess.run(command + ['collated', str(root), 'none', 'none', str(ROOT / 'packages/runtime/data')], capture_output=True, text=True, timeout=120)
            assert result.returncode == 0, result.stderr[-1000:]
            actual = base64.b64decode([l for l in result.stdout.splitlines() if l.startswith('text:')][0][5:]).decode()
            assert actual == expected, (backend, actual, expected)
            print('%s: ls order matches Node localeCompare for %d entries' % (backend, len(NAMES) + len(DIRS)))

main()
