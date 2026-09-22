"""Filesystem execution and cancellation contracts of the write tool core.

Public tool-definition, path-input and renderer integration are still pending.
"""
import sys
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/write-tool'

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']),
                         ('native-1', [str(PREFIX), '--threads', '1']),
                         ('native-4', [str(PREFIX), '--threads', '4'])]:
    if len(sys.argv) > 1 and backend not in sys.argv[1:]:
        continue
    with tempfile.TemporaryDirectory(prefix='bend-write-') as folder:
        root = Path(folder)

        def run(*args):
            result = subprocess.run(command + list(map(str, args)), cwd=root,
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0 and not result.stderr and result.stdout.strip() == 'ok', (backend, args, result)

        target = root / 'nested/dir/é😀.txt'
        run('write', target, 'Hello\n漢字\n')
        assert target.read_bytes() == 'Hello\n漢字\n'.encode()
        run('write', target, 'short')
        assert target.read_text() == 'short'
        run('write', target, '')
        assert target.read_bytes() == b''
        run('cancel', root / 'uncreated/child', 'never written')
        assert not (root / 'uncreated').exists()
        for mode in ['mkdir-abort', 'mkdir-failure', 'write-abort', 'write-failure']:
            staged = root / mode / 'child'
            run('stage', mode, staged)
            assert staged.parent.is_dir()
            if mode.startswith('mkdir'):
                assert not staged.exists()
            else:
                assert staged.read_text() == 'written'
        for _ in range(8):
            run('inflight', target)
            assert target.read_text() == 'second'
        print(f'{backend}: write bytes, overwrite, recursive mkdir, pre-abort and in-flight abort serialization PASS', flush=True)
