"""Pinned pi ScrollView state and direct viewport differential."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
expected = b''.join(subprocess.check_output(['bun', source], cwd=root) for source in [
    'tests/scroll_view_reference.ts', 'tests/scroll_layout_reference.ts'
])
for backend, command in [
    ('Bun', ['bun', 'build/bend-process-files/bend2/main.ts', 'tests/scroll-layout.bend']),
    ('native-1', ['build/scroll-layout', '--threads', '1']),
    ('native-4', ['build/scroll-layout', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: ScrollView state and direct viewport match upstream')
