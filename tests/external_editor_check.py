"""External-editor contract and foreground-stdio checks on native Bend."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--editor', type=Path, default=ROOT / 'build/external-editor')
parser.add_argument('--process', type=Path, default=ROOT / 'build/process-inherited')
args = parser.parse_args()


def run(binary, threads, *values, **kwargs):
    result = subprocess.run([str(binary), '--threads', str(threads), *values],
                            capture_output=True, text=True, timeout=10, **kwargs)
    assert result.returncode == 0, (result.stdout, result.stderr)
    return result


def foreground(threads, folder):
    master, slave = pty.openpty()

    def terminal_owner():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    command = ('import os; '
               'assert os.getpgrp()==os.tcgetpgrp(0); '
               'assert os.getsid(0)==os.getsid(os.getppid()); '
               'assert all(os.isatty(fd) for fd in (0,1,2)); '
               'print("ready",flush=True); '
               'print("read:"+input(),flush=True); '
               'os.write(2,b"stderr-ok\\n")')
    child = subprocess.Popen([str(args.process), '--threads', str(threads),
                              shutil.which('python3'), str(folder), '-c', command],
                             stdin=slave, stdout=slave, stderr=slave, preexec_fn=terminal_owner)
    os.close(slave)
    output = b''
    sent = False
    deadline = time.monotonic() + 10
    try:
        while time.monotonic() < deadline:
            if not select.select([master], [], [], .1)[0]:
                continue
            try:
                block = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not block:
                break
            output += block
            if b'ready\r\n' in output and not sent:
                os.write(master, b'editor-input\n')
                sent = True
        assert child.wait(timeout=1) == 0, output
        assert all(token in output for token in
                   [b'read:editor-input', b'stderr-ok', b'exit:0']), output
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)


with tempfile.TemporaryDirectory(prefix='pi-external-editor-test-') as temporary:
    folder = Path(temporary)
    fixture = folder / 'editor.py'
    capture = folder / 'capture.json'
    fixture.write_text('''import json, os, pathlib, signal, sys
capture, mode, filename = sys.argv[1:]
path = pathlib.Path(filename)
pathlib.Path(capture).write_text(json.dumps({
    "filePath": filename, "content": path.read_text(),
    "entries": sorted(p.name for p in path.parent.iterdir()),
    "directoryMode": path.parent.stat().st_mode & 0o777,
}))
if mode == "fail": sys.exit(7)
if mode == "signal": os.kill(os.getpid(), signal.SIGTERM)
outputs = {"edited": b"edited\\n", "empty": b"", "bom": b"\\xef\\xbb\\xbfhello\\n", "invalid": b"\\xff\\n",
           "lines": b"one\\ntwo\\n\\n", "crlf": b"hello\\r\\n", "unicode": "日本語 😀\\n".encode()}
path.write_bytes(outputs[mode])
''')
    for threads in [1, 4]:
        foreground(threads, folder)
        result = run(args.process, threads, '/bin/sh', str(folder), '-c',
                     'read line; printf "out:%s\\n" "$line"; printf err >&2; exit 7', input='hello\n')
        assert result.stdout == 'out:hello\nexit:7\n' and result.stderr == 'err', result
        assert run(args.process, threads, '/missing/editor', str(folder)).stdout == 'spawn-error:2\n'
        assert run(args.process, threads, '/bin/sh', str(folder / 'missing')).stdout == 'spawn-error:2\n'
        assert run(args.process, threads, '/bin/sh', str(folder), '-c', 'kill -PIPE $$').stdout == 'signal:13\n'
        private = Path(run(args.process, threads, 'temp', str(folder / 'private-XXXXXX')).stdout.strip())
        assert private.is_dir() and private.stat().st_mode & 0o077 == 0
        private.rmdir()
        assert run(args.process, threads, 'temp', str(folder / 'invalid')).stdout == 'temp-error:22\n'

        cases = [('edited', 'edited'), ('fail', None), ('empty', ''), ('signal', None),
                 ('bom', 'hello'), ('lines', 'one\ntwo\n'), ('crlf', 'hello\r'), ('unicode', '日本語 😀'), ('invalid', None)]
        for mode, expected in cases:
            command = f'{shutil.which("python3")} {fixture} {capture} {mode}'
            reference = subprocess.run(['bun', str(ROOT / 'tests/external_editor_reference.mts'), command, 'original'],
                                       capture_output=True, timeout=10)
            assert reference.returncode == 0 and not reference.stderr, reference
            reference_result = json.loads(reference.stdout.decode().rsplit('reference:', 1)[1])
            reference_expected = ({'status': 'complete', 'content': '�'} if mode == 'invalid' else
                                  {'status': 'failed'} if expected is None else
                                  {'status': 'complete', 'content': expected})
            assert reference_result == reference_expected, reference_result
            # Binary output is decoded without universal-newline conversion: CRLF
            # editing removes only the final LF, preserving the preceding CR.
            result = subprocess.run([str(args.editor), '--threads', str(threads), command, 'original'],
                                    capture_output=True, timeout=10)
            assert result.returncode == 0 and not result.stderr, result
            suffix = 'failed\n' if expected is None else 'complete:' + expected + '\n'
            assert result.stdout.decode().endswith(suffix), (mode, result.stdout)
            observed = json.loads(capture.read_text())
            directory = Path(observed['filePath']).parent
            assert directory.parent == Path(tempfile.gettempdir()) and directory.name.startswith('pi-editor-')
            assert Path(observed['filePath']).name == 'prompt.md'
            assert observed['entries'] == ['prompt.md'] and observed['content'] == 'original'
            assert observed['directoryMode'] & 0o077 == 0 and not directory.exists()
        assert run(args.editor, threads, '/missing/editor', 'original').stdout.endswith('failed\n')
        print(f'native{threads}: external editor success/failure/empty, text normalization, cleanup, foreground stdio')
