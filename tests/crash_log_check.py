"""upstream crash-log.test.ts plus the native crash-log file cases (tests/crash-log.bend) on Bun/native lanes.

Each lane runs in a fresh scratch directory.
Usage: python3 tests/crash_log_check.py [build/crash-log.js] [build/crash-log]
"""
import os, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/crash-log.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/crash-log'
lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/crash-log.bend first'
for name, command in lanes:
    with tempfile.TemporaryDirectory(prefix='pi-crash-log-') as directory:
        result = subprocess.run(command + [directory], cwd=root, capture_output=True, text=True, timeout=300)
    lines = result.stdout.splitlines()
    assert result.returncode == 0 and len(lines) == 8 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr[-3000:])
    print(f'{name}: {len(lines)} crash-log cases pass')
