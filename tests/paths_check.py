"""upstream paths.test.ts and path-utils.test.ts on the Bun and native lanes.

Creates one fixture directory per upstream temporary directory, then runs
tests/paths.bend, which makes the upstream assertions itself. Usage:
  python3 tests/paths_check.py [build/paths.js] [build/paths]
"""
import os, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/paths.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/paths'


def fixture(base: pathlib.Path) -> None:
    def write(path: str, text: str = 'content') -> None:
        target = base / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    write('regular/file.txt', 'hello')
    write('symlink/target.txt', 'hello')
    (base / 'symlink/link.txt').symlink_to(base / 'symlink/target.txt')
    (base / 'directory/target-dir').mkdir(parents=True)
    (base / 'directory/link-dir').symlink_to(base / 'directory/target-dir', target_is_directory=True)
    (base / 'missing').mkdir()
    (base / 'dangling').mkdir()
    (base / 'dangling/link.txt').symlink_to(base / 'dangling/target.txt')
    (base / 'urls').mkdir()
    (base / 'percent').mkdir()
    write('read-existing/test-file.txt')
    write('read-nfd/fileé.txt')
    write('read-curly/Capture d’cran.txt')
    write('read-combined/Capture d’écran.txt')
    write('read-ampm/Screenshot 2024-01-01 at 10.00.00 AM.png')
    write('read-ampm-lower/Screenshot 2024-01-01 at 10.00.00 am.png')


lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/paths.bend first'
for name, command in lanes:
    with tempfile.TemporaryDirectory(prefix='pi-paths-') as directory:
        base = pathlib.Path(directory)
        fixture(base)
        result = subprocess.run(command + [str(base), os.path.realpath(base), '/home/pi-paths-home'], cwd=root, capture_output=True, text=True, timeout=120)
        lines = result.stdout.splitlines()
        assert result.returncode == 0 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr)
        print(f'{name}: {len(lines)} paths/path-utils cases pass')
