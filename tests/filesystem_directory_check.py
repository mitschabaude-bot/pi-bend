"""Real filesystem metadata snapshots: bytes, types, errors, order and retirement."""
import argparse
import base64
import errno
import os
from pathlib import Path
import socket
import stat
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/filesystem-directory')
a = p.parse_args()


def kind(mode):
    return ('file' if stat.S_ISREG(mode) else 'directory' if stat.S_ISDIR(mode)
            else 'symlink' if stat.S_ISLNK(mode) else 'other')


def expected(directory):
    raw = os.fsencode(directory)
    return [(name, kind(os.lstat(raw + b'/' + name).st_mode)) for name in os.listdir(raw)]


for backend in a.backends:
    command = ['bun', str(a.prefix) + '.js'] if backend == 'bun' else [str(a.prefix), '--threads', backend[-1]]
    checks = 0

    def run(mode, path):
        global checks
        result = subprocess.run(command + [mode, str(path)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, (backend, mode, path, result.stdout, result.stderr)
        checks += 1
        return result.stdout.splitlines()

    def entries(mode, path):
        return [(base64.b64decode(name, validate=True), value) for name, value in
                (line.split('|') for line in run(mode, path))]

    with tempfile.TemporaryDirectory(prefix='bend directory ') as folder, socket.socket(socket.AF_UNIX) as endpoint:
        path = Path(folder)
        directory = path / 'entries'
        directory.mkdir()
        empty = path / 'empty'
        empty.mkdir()
        denied = path / 'denied'
        denied.mkdir()
        (denied / 'child').write_text('private')
        for name in ['z-last', 'a-first', 'é雪😀', '\ufeffbom', 'new\nline', 'space name']:
            (directory / name).write_text(name)
        (directory / 'subdirectory').mkdir()
        (directory / 'file-link').symlink_to('z-last')
        (directory / 'directory-link').symlink_to('subdirectory')
        (directory / 'broken-link').symlink_to('missing')
        (directory / 'cycle-link').symlink_to('cycle-link')
        os.mkfifo(directory / 'fifo')
        endpoint.bind(str(directory / 'socket'))
        assert entries('raw', directory) == expected(directory), backend
        assert entries('list', directory) == expected(directory), backend
        for name, value in expected(directory):
            target = directory / os.fsdecode(name)
            try:
                result = [kind(os.stat(target).st_mode)]
            except OSError as error:
                result = [f'error:{error.errno}']
            assert run('kind', target) == result, (backend, target, result)
        assert run('list', empty) == run('raw', empty) == []
        assert run('kind', directory / 'directory-link') == ['directory']
        assert entries('list', directory / 'directory-link') == []
        assert run('list', directory / 'file-link') == [f'error:{errno.ENOTDIR}']
        for mode in ['raw', 'list', 'kind']:
            assert run(mode, path / 'missing') == [f'error:{errno.ENOENT}']
            assert run(mode, '') == [f'error:{errno.ENOENT}']
        for mode in ['kind-nul', 'list-nul']:
            assert run(mode, directory) == [f'error:{errno.EILSEQ}']
        denied.chmod(0)
        try:
            assert run('list', denied) == [f'error:{errno.EACCES}']
            assert run('kind', denied / 'child') == [f'error:{errno.EACCES}']
        finally:
            denied.chmod(0o700)
        # The primitive preserves arbitrary filename bytes; the typed wrapper
        # reports malformed UTF-8 instead of silently replacing filenames.
        invalid = os.fsencode(directory) + b'/invalid-\xff'
        fd = os.open(invalid, os.O_CREAT | os.O_WRONLY, 0o600)
        os.close(fd)
        assert entries('raw', directory) == expected(directory)
        assert run('list', directory) == ['invalid-utf8']
        os.unlink(invalid)
        started = time.monotonic()
        before, after = map(int, run('repeat', directory)[0].split('|'))
        elapsed = time.monotonic() - started
        assert before == after and before < 32, (backend, before, after)
        large = path / 'large'
        large.mkdir()
        for number in range(2048):
            (large / f'entry-{number:04}').touch()
        started = time.monotonic()
        assert entries('list', large) == expected(large)
        large_elapsed = time.monotonic() - started
        assert run('list', empty) == []
        print(f'{backend}: {checks} checks PASS; 256 snapshot/stat cycles {elapsed:.3f}s, '
              f'2048-entry typed snapshot {large_elapsed:.3f}s; descriptors {before}->{after}', flush=True)
