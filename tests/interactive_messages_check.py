"""Byte-exact interactive message rendering against pinned pi-mono sources."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
env = dict(os.environ)
env.pop('NO_COLOR', None)
env.update(FORCE_COLOR='1', TERM='xterm-256color')
expected = subprocess.check_output(['bun', 'tests/interactive_messages_reference.ts'], cwd=root, env=env)
for backend, command in [
    ('Bun', [str(root / 'build/bend-process-files/bend2/main.ts'), 'tests/interactive-messages.bend']),
    ('native-1', ['build/interactive-messages', '--threads', '1']),
    ('native-4', ['build/interactive-messages', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root, env=env)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: 11 interactive message snapshots match upstream bytes')
