"""Tool execution cells and styles against hash-pinned pi-mono sources."""
from pathlib import Path
import os
import argparse
import json
import subprocess

root = Path(__file__).resolve().parents[1]
env = dict(os.environ)
env.pop('NO_COLOR', None)
env.update(FORCE_COLOR='1', TERM='xterm-256color')
parser = argparse.ArgumentParser()
parser.add_argument('--bun-runner', help='Previously compiled JavaScript fixture')
parser.add_argument('--native-runner', default='build/tool-execution')
args = parser.parse_args()
bun_command = ['bun', args.bun_runner] if args.bun_runner else ['bun', 'build/bend-native-toolchain/bend2/main.ts', 'tests/tool-execution.bend']
expected = subprocess.check_output(['bun', 'tests/tool_execution_reference.ts'], cwd=root, env=env)
frame_count = len(expected.decode().rstrip('\n').split('\n'))
for backend, command in [
    ('Bun', bun_command),
    ('native-1', [args.native_runner, '--threads', '1']),
    ('native-4', [args.native_runner, '--threads', '4']),
]:
    actual = subprocess.check_output(command, cwd=root, env=env)
    if actual != expected:
        subprocess.run(["bun", "tests/tool_execution_cells.ts"], cwd=root, env=env, input=json.dumps([expected.decode(), actual.decode()]).encode(), check=True)
    print(f'{backend}: {frame_count} tool execution display snapshots match upstream cells and styles')
