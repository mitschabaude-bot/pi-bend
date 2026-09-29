"""Byte-exact footer snapshots against the f07218c4d upstream component."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
compiler = os.environ.get('BEND_COMPILER', str(root / 'build/bend-process-files/bend2/main.ts'))
env = dict(os.environ)
env.pop('NO_COLOR', None)
env.update(FORCE_COLOR='1', TERM='xterm-256color')
expected = subprocess.check_output(['bun', 'tests/footer_reference.ts'], cwd=root, env=env)
snapshots = {
    label: [line for line in rendered.split('\x1f')]
    for label, rendered in (
        row.split('\x1e', 1) for row in expected.decode().strip().split('\n')
    )
}
assert snapshots['home'][0].find('~') >= 0
assert '/home/user2' in snapshots['cumulative'][0]
assert '$1.250' in snapshots['cumulative'][1]
assert 'CH25.0%' in snapshots['cache'][1]
assert '$1.234 (sub)' in snapshots['kimi'][1]
assert '$0.000 (sub)' in snapshots['subscription'][1]
assert '$1.234' in snapshots['oauth'][1] and '(sub)' not in snapshots['oauth'][1]
for backend, command in [
    ('Bun', ['bun', compiler, 'tests/footer.bend']),
    ('native-1', [os.environ.get('FOOTER_BEND', 'build/footer'), '--threads', '1']),
    ('native-4', [os.environ.get('FOOTER_BEND', 'build/footer'), '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root, env=env)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: {len(snapshots)} footer snapshots match upstream bytes')
