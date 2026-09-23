"""Pinned upstream Loader snapshots plus native spinner/cancellation lifecycle."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ORACLE = subprocess.check_output(['bun', 'tests/loader-reference.ts', '/home/agent/code/pi-mono'], cwd=ROOT, text=True).splitlines()
for name, command in [
    ('bun', ['bun', 'build/loader.js']),
    ('native-1', ['build/loader', '--threads', '1']),
    ('native-4', ['build/loader', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=ROOT, text=True, timeout=20).splitlines()
    assert actual[:len(ORACLE)] == ORACLE, (name, ORACLE, actual)
    assert actual[len(ORACLE):] == ['False/True/3'], (name, actual)
    print(f'{name}: {len(ORACLE)} pinned displays; cancellation, redraw, and timer lifecycle passed')
