"""Compare Box rendering, invalidation and padded mouse routing with pinned upstream."""
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/box_reference.ts'], cwd=root)
for backend, command in [
    ('bun', ['bun', 'build/box.js']),
    ('native-1', ['build/box', '--threads', '1']),
    ('native-4', ['build/box', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, actual, expected)
    print(f'{backend}: Box behavior matches upstream')
