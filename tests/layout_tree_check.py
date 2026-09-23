"""Pinned upstream differential for recursive viewport layout."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/layout_tree_reference.ts'], cwd=root)
for backend, command in [
    ('Bun', ['bun', 'build/bend-process-files/bend2/main.ts', 'tests/layout-tree.bend']),
    ('native-1', ['build/layout-tree', '--threads', '1']),
    ('native-4', ['build/layout-tree', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: recursive viewport layout matches upstream')
