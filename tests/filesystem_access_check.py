"""Access permissions and errno names against the host OS; all files are temporary."""
import errno
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/filesystem-access'
with tempfile.TemporaryDirectory(prefix='bend-access-') as directory:
    root = Path(directory)
    target = root / 'é漢😀'
    target.write_bytes(b'unchanged\x00bytes')
    alias = root / 'alias'
    alias.symlink_to(target)
    dangling = root / 'dangling'
    dangling.symlink_to(root / 'missing')
    for backend, command in [('bun', ['bun', str(PREFIX)+'.js']),
                             ('native-1', [str(PREFIX), '--threads', '1']),
                             ('native-4', [str(PREFIX), '--threads', '4'])]:
        def run(*args):
            result = subprocess.run(command + list(map(str, args)), capture_output=True, text=True, timeout=20)
            assert result.returncode == 0 and not result.stderr, (backend, result)
            return result.stdout.strip()
        for permissions in [0o000, 0o200, 0o400, 0o600, 0o700]:
            target.chmod(permissions)
            for path in [target, alias, root, root/'missing', dangling, target/'child', '']:
                for mode in range(8):
                    expected = os.access(path, mode)
                    actual = run('access', path, mode)
                    assert (actual == 'ok') == expected, (backend, permissions, path, mode, actual, expected)
        target.chmod(0o600)
        for path, code in [(root/'missing', errno.ENOENT), (target/'child', errno.ENOTDIR)]:
            assert run('access', path, 6).startswith(f'{code}:'), (backend, path)
        assert run('access', target, 8).startswith(f'{errno.EINVAL}:')
        assert run('nul', target).startswith(f'{errno.EILSEQ}:')
        for code in [errno.ENOENT, errno.EACCES, errno.EISDIR]:
            assert run('name', code) == errno.errorcode[code], (backend, code)
        for code in [0, 123456, 4294967295]:
            assert run('name', code) == 'none', (backend, code)
        assert target.read_bytes() == b'unchanged\x00bytes'
        print(f'{backend}: access modes, aliases, errno names and unchanged content PASS', flush=True)
