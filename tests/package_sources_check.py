"""upstream package-manager-ssh.test.ts and the source-management blocks of
package-manager.test.ts (tests/package-sources.bend) on Bun/native lanes.

Each lane gets a fresh temporary directory with an agent/ folder, as the
upstream beforeEach creates. The first run creates the temporary extension
folder; its mode is passed to the second run, which makes the assertions.
Usage: python3 tests/package_sources_check.py [build/package-sources.js] [build/package-sources]
"""
import os, pathlib, stat, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/package-sources.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/package-sources'
lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/package-sources.bend first'
for name, command in lanes:
    with tempfile.TemporaryDirectory(prefix='pm-test-') as directory:
        temp = pathlib.Path(directory)
        (temp / 'agent').mkdir()
        home = temp / 'home'
        home.mkdir()
        first = subprocess.run(command + [str(temp), str(home)], cwd=root, capture_output=True, text=True, timeout=300)
        assert first.returncode == 0 and first.stdout.strip() == 'created', (name, first.stdout, first.stderr)
        mode = stat.S_IMODE((temp / 'agent/tmp/extensions').stat().st_mode)
        result = subprocess.run(command + [str(temp), str(home), str(mode)], cwd=root, capture_output=True, text=True, timeout=300)
        lines = result.stdout.splitlines()
        assert result.returncode == 0 and len(lines) == 30 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr)
        print(f'{name}: {len(lines)} package source cases pass')
