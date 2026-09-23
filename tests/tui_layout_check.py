"""TuiBase retained ScrollView viewport against pinned upstream layout/scroll sources."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/tui_layout_reference.ts'], cwd=root)
for backend, command in [
    ('Bun', ['bun', 'build/bend-process-files/bend2/main.ts', 'tests/tui-layout.bend']),
    ('native-1', ['build/tui-layout', '--threads', '1']),
    ('native-4', ['build/tui-layout', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: TuiBase scroll, commit, and resize match upstream')
