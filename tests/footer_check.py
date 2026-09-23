"""Byte-exact footer snapshots against the f07218c4d upstream component."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
compiler = os.environ.get('BEND_COMPILER', '/tmp/pi-bend-theme-controller/build/theme-toolchain/bend2/main.ts')
env = dict(os.environ)
env.pop('NO_COLOR', None)
env.update(FORCE_COLOR='1', TERM='xterm-256color')
expected = subprocess.check_output(['bun', 'tests/footer_reference.ts'], cwd=root, env=env)
for backend, command in [
    ('Bun', ['bun', compiler, 'tests/footer.bend']),
    ('native-1', ['build/footer', '--threads', '1']),
    ('native-4', ['build/footer', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root, env=env)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: six footer snapshots match upstream bytes')
