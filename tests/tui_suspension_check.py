"""Repeated terminal handoffs: cooked editor input, raw UI resume, clean exit."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', type=Path, default=ROOT / 'build/tui-suspension')
args = parser.parse_args()


def check(threads, mode, cycles, folder):
    capture = folder / f'{threads}-{mode}.json'
    editor = folder / 'editor.py'
    editor.write_text('''import json, os, pathlib, sys, termios
capture, mode, filename = sys.argv[1:]
path = pathlib.Path(filename)
assert os.isatty(0) and os.isatty(1)
assert os.getpgrp() == os.tcgetpgrp(0)
assert termios.tcgetattr(0)[3] & (termios.ICANON | termios.ECHO) == (termios.ICANON | termios.ECHO)
previous = json.loads(pathlib.Path(capture).read_text()) if pathlib.Path(capture).exists() else []
count = len(previous) + 1
previous.append({"content": path.read_text(), "directory": str(path.parent),
                 "fds": len(os.listdir(f"/proc/{os.getppid()}/fd"))})
pathlib.Path(capture).write_text(json.dumps(previous))
print(f"external-ready:{count}", flush=True)
line = input()
assert line == f"input-{count}"
path.write_text("" if mode == "empty" else f"after{count}\\n")
sys.exit(7 if mode == "fail" else 0)
''')
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    original = termios.tcgetattr(slave)

    def terminal_owner():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    command = f'{shutil.which("python3")} {editor} {capture} {mode}'
    child = subprocess.Popen([str(args.binary), '--threads', str(threads), command],
                             stdin=slave, stdout=slave, stderr=subprocess.PIPE,
                             preexec_fn=terminal_owner,
                             env={**os.environ, 'TERM': 'xterm-256color', 'PI_TUI_ESC_TIMEOUT': '10'})
    output, errors = bytearray(), bytearray()

    def wait_for(token, stderr=False, count=1):
        deadline = time.monotonic() + 15
        selected = errors if stderr else output
        while selected.count(token) < count and time.monotonic() < deadline:
            for fd in select.select([master, child.stderr], [], [], .1)[0]:
                try:
                    block = os.read(fd if isinstance(fd, int) else fd.fileno(), 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    block = b''
                (output if fd == master else errors).extend(block)
            assert child.poll() is None, (child.returncode, errors[-2000:])
        assert selected.count(token) >= count, (token, output[-2000:], errors[-2000:])

    try:
        wait_for(b'ready\n', stderr=True)
        wait_for(b'before')
        for cycle in range(1, cycles + 1):
            start = len(output)
            os.write(master, b'g')
            wait_for(f'external-ready:{cycle}'.encode())
            assert b'\x1b[?25h' in output[start:], 'editor inherited a hidden cursor'
            assert termios.tcgetattr(slave) == original, 'editor did not receive original terminal settings'
            os.write(master, f'input-{cycle}\n'.encode())
            wait_for(b'resumed\n', stderr=True, count=cycle)
            assert not termios.tcgetattr(slave)[3] & termios.ICANON, 'UI did not resume raw input'
            if mode == 'edited':
                wait_for(f'after{cycle}'.encode())
        os.write(master, b'q')
        _, remaining = child.communicate(timeout=15)
        errors.extend(remaining)
        assert child.returncode == 0, errors.decode(errors='replace')
        assert errors.count(b'ready\n') == 1 and errors.count(b'resumed\n') == cycles, errors
        assert errors.count(b'stopping:True\n') == cycles and errors.count(b'stopping:False\n') == 1, errors
        assert errors.count(b'editor:failed\n') == (cycles if mode == 'fail' else 0), errors
        assert termios.tcgetattr(slave) == original, 'exit did not restore terminal settings'
        captures = json.loads(capture.read_text())
        expected = ['before'] + ([f'after{i}' for i in range(1, cycles)] if mode == 'edited' else ['before'] * (cycles - 1))
        assert [entry['content'] for entry in captures] == expected, captures
        assert len({entry['fds'] for entry in captures}) == 1, captures
        assert all(not Path(entry['directory']).exists() for entry in captures), captures
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)
        os.close(slave)
    print(f'native{threads} {mode}: {cycles} cooked/raw handoffs, preserved content, stable descriptors, terminal restored')


with tempfile.TemporaryDirectory(prefix='pi-suspend-') as temporary:
    for threads in [1, 4]:
        for mode, cycles in [('edited', 3), ('fail', 2), ('empty', 1)]:
            check(threads, mode, cycles, Path(temporary))
