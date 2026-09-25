"""Compare stack rendering and direct-child viewport geometry with pinned pi-mono."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
expected = subprocess.check_output(['bun', 'tests/stack_reference.ts'], cwd=root)
for backend, command in [
    ('Bun', ['bun', 'build/bend-native-toolchain/bend2/main.ts', 'tests/stack.bend']),
    ('native-1', ['build/stack', '--threads', '1']),
    ('native-4', ['build/stack', '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root)
    assert actual == expected, (backend, actual.decode(), expected.decode())
    print(f'{backend}: stack and direct-child viewport behavior matches upstream')
