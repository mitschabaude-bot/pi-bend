"""Byte-exact tool execution display against hash-pinned pi-mono sources."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
env = dict(os.environ)
env.pop('NO_COLOR', None)
env.update(FORCE_COLOR='1', TERM='xterm-256color')
expected = subprocess.check_output(['bun', 'tests/tool_execution_reference.ts'], cwd=root, env=env)
for backend, command in [
    ('Bun', ['bun', '/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts', 'tests/tool-execution.bend']),
    ('native-1', ['build/tool-execution', '--threads', '1']),
    ('native-4', ['build/tool-execution', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root, env=env)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: 18 tool execution display snapshots match upstream bytes')
