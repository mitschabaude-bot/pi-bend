"""Pinned upstream theme setting, environment, and RGB classification parity."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/theme-detection-reference.ts'], cwd=root)
for backend, command in [
    ('bun', ['bun', 'build/theme-detection.js']),
    ('native-1', ['build/theme-detection', '--threads', '1']),
    ('native-4', ['build/theme-detection', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, next((i for i, (a, b) in enumerate(zip(actual.splitlines(), expected.splitlines())) if a != b), None))
    print(f'{backend}: {len(expected.splitlines())} theme detection cases match pinned pi')
