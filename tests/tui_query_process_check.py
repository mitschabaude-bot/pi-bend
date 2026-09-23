"""Drive terminal query interception and ordinary focus input through a real PTY."""
import errno
import fcntl
import os
import pathlib
import pty
import select
import struct
import subprocess
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ESC = b'\x1b'
for backend, command in [('Bun', ['bun', 'build/tui-query-write-error.js']), ('native1', ['build/tui-query-write-error', '--threads', '1']), ('native4', ['build/tui-query-write-error', '--threads', '4'])]:
    actual = subprocess.check_output(command, cwd=ROOT, text=True, timeout=5).strip()
    assert actual == 'True:closed', (backend, actual)
    print(f'{backend}: query write failure stops process and retains error')
for backend, command in [
    ('native1', ['build/tui-query-process', '--threads', '1']),
    ('native4', ['build/tui-query-process', '--threads', '4']),
]:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    original = termios.tcgetattr(slave)
    process = subprocess.Popen(command, cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env={**os.environ, 'TERM': 'xterm-256color'})
    output = bytearray()
    def until(needle):
        deadline = time.monotonic() + 8
        while needle not in output and time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
        assert needle in output, (backend, needle, bytes(output), process.poll(), process.stderr.read().decode(errors='replace') if process.poll() is not None else '')
    try:
        until(ESC + b']11;?\x07')
        os.write(master, ESC + b']11;#ff8040\x07')
        until((ESC + b']11;?\x07') * 2)
        os.write(master, ESC + b']11;not-a-color\x07')
        until(ESC + b'[?996n')
        os.write(master, ESC + b'[?997;2n')
        until(b'hello')
        os.write(master, b'x')
        stderr = process.communicate(timeout=8)[1].decode(errors='replace')
        assert process.returncode == 0, (backend, stderr)
        while select.select([master], [], [], 0)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
        assert output.count(ESC + b'[?2031h') == 1 and output.count(ESC + b'[?2031l') == 1, (backend, bytes(output))
        assert stderr.splitlines() == ['background:255,128,64', 'malformed:none', 'scheme:light', 'redrawn', 'input:x', 'stopping', 'done'], (backend, stderr)
        assert termios.tcgetattr(slave) == original, backend
        print(f'{backend}: OSC 11, malformed reply, color scheme and ordinary input passed')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
