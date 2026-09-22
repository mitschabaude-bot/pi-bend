"""Exercise native filesystem primitives and the pure Bend file operations.

Uses only temporary directories except /dev/full for a typed write failure.
Set BEND to the filesystem primitive candidate until the patch is installed.
"""
import errno
import os
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/filesystem-paths'

def limits():
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
    os.umask(0o027)

def text(value):
    return 'ok:' + ','.join(str(ord(c)) for c in str(value))

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']),
                         ('native-1', [str(PREFIX), '--threads', '1']),
                         ('native-4', [str(PREFIX), '--threads', '4'])]:
    with tempfile.TemporaryDirectory(prefix='bend-filesystem-') as folder:
        root = Path(folder)
        def run(*args, cwd=root):
            result = subprocess.run(command + list(map(str, args)), cwd=cwd,
                                    capture_output=True, text=True, timeout=20,
                                    preexec_fn=limits)
            assert result.returncode == 0 and not result.stderr, (backend, args, result.returncode, result.stderr)
            return result.stdout.strip()

        assert run('cwd') == text(root)
        private = root / 'private'
        assert run('open', private, 'w') == 'ok'
        assert private.stat().st_mode & 0o777 == 0o600
        private.write_text('keep')
        assert run('open', private, 'a') == 'ok'
        assert run('open', private, 'r') == 'ok'
        assert private.read_text() == 'keep'
        assert run('open', root / 'no-create', '?') == f'error:{errno.EINVAL}'
        assert not (root / 'no-create').exists()
        assert run('open', root / 'missing', 'r') == f'error:{errno.ENOENT}'
        assert run('mkdir', '') == f'error:{errno.ENOENT}'
        assert run('mkdir', '/') == 'ok'
        assert run('mkdir', 'nested/é漢😀/leaf/') == 'ok'
        leaf = root / 'nested/é漢😀/leaf'
        assert leaf.is_dir() and (leaf.stat().st_mode & 0o777) == 0o750
        assert run('mkdir', leaf) == 'ok'
        assert run('realpath', 'nested/é漢😀/leaf/../leaf') == text(leaf)
        assert run('cwd', cwd=leaf) == text(leaf)
        assert run('write', leaf / 'content.txt', 'text é漢😀\n') == 'ok'
        assert (leaf / 'content.txt').read_bytes() == 'text é漢😀\n'.encode()
        assert run('write', leaf / 'content.txt', 'x') == 'ok'
        assert (leaf / 'content.txt').read_bytes() == b'x'
        assert run('mkdir', leaf / 'content.txt') == f'error:{errno.EEXIST}'
        assert run('mkdir', leaf / 'content.txt/child') == f'error:{errno.ENOTDIR}'
        assert run('write', root / 'absent/child', 'x') == f'error:{errno.ENOENT}'
        assert run('realpath', root / 'absent') == f'error:{errno.ENOENT}'
        assert run('realpath', leaf / 'content.txt/child') == f'error:{errno.ENOTDIR}'
        assert run('write', leaf, 'x') == f'error:{errno.EISDIR}'
        assert run('nul', root / 'invalid') == f'error:{errno.EILSEQ}|error:{errno.EILSEQ}'
        assert not (root / 'invalid').exists()

        (root / 'alias').symlink_to(leaf, target_is_directory=True)
        assert run('realpath', root / 'alias') == text(leaf)
        assert run('mkdir', root / 'alias') == 'ok'
        assert run('write', root / 'alias/content.txt', 'via alias') == 'ok'
        assert (leaf / 'content.txt').read_text() == 'via alias'
        assert run('mkdir', root / 'alias/../sibling') == 'ok'
        assert (leaf.parent / 'sibling').is_dir()
        assert not (root / 'sibling').exists()
        (root / 'loop').symlink_to('loop')
        assert run('realpath', root / 'loop') == f'error:{errno.ELOOP}'
        (root / 'broken').symlink_to('absent')
        assert run('mkdir', root / 'broken') == f'error:{errno.ENOENT}'

        # A replacement character must never redirect a filesystem operation.
        invalid = os.fsencode(root) + b'/invalid-\xff'
        os.mkdir(invalid)
        os.symlink(invalid, os.fsencode(root / 'nonutf8'))
        assert run('bytes', root / 'nonutf8') == 'ok:' + ','.join(map(str, invalid))
        assert run('realpath', root / 'nonutf8') == 'encoding'
        assert run('cwd', cwd=invalid) == 'encoding'

        if os.geteuid() != 0:
            denied = root / 'denied'
            denied.mkdir(mode=0)
            try:
                assert run('mkdir', denied / 'child') == f'error:{errno.EACCES}'
            finally:
                denied.chmod(0o700)

        assert run('repeat', root / 'repeated').splitlines() == ['ok'] * 128
        if Path('/dev/full').exists():
            assert run('repeat', '/dev/full').splitlines() == [f'error:{errno.ENOSPC}'] * 128

        # OS-level races cannot turn an existing directory into an error.
        peers = [subprocess.Popen(command + ['mkdir', str(root / 'raced/a/b')],
                                  cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, preexec_fn=limits) for _ in range(8)]
        for peer in peers:
            stdout, stderr = peer.communicate(timeout=20)
            assert peer.returncode == 0 and not stderr and stdout.strip() == 'ok'
    print(f'{backend}: filesystem paths, Unicode, races and handle retirement PASS', flush=True)
