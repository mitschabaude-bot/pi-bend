"""Compare native Flash rendering and expiry order with pinned pi-mono source."""
from upstream_pin import UPSTREAM
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/alt-screen-flash-reference.ts', str(UPSTREAM)], cwd=ROOT, text=True).splitlines()
for name, command in [
    ('bun', ['bun', 'build/alt-screen-flash.js']),
    ('native-1', ['build/alt-screen-flash', '--threads', '1']),
    ('native-4', ['build/alt-screen-flash', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=ROOT, text=True, timeout=20).splitlines()
    assert actual == expected, (name, expected, actual)
    print(f'{name}: {len(expected)-1} pinned snapshots, ordered expiry, redraw, and disposal passed')
