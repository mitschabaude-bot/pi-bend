"""Exercise automatic theme selection and live scheme changes through a PTY."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
ESC = b'\x1b'
for threads in (1, 4):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    saved = termios.tcgetattr(slave)
    process = subprocess.Popen(['build/theme-controller-process', '--threads', str(threads)], cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env={**os.environ, 'TERM': 'xterm-256color'})
    output = bytearray()
    def until(needle):
        deadline = time.monotonic() + 8
        while needle not in output and time.monotonic() < deadline:
            if select.select([master], [], [], .2)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
        assert needle in output, (threads, needle, bytes(output))
    try:
        until(ESC + b'[?996n')
        until(ESC + b']11;?\x07')
        os.write(master, ESC + b'[?997;2n')
        os.write(master, ESC + b']11;#000000\x07')
        until(ESC + b'[?2031h')
        os.write(master, ESC + b'[?997;1n')
        until(b'theme frame')
        os.write(master, b's')
        until(ESC + b'[?2031l')
        os.write(master, b'x')
        stderr = process.communicate(timeout=8)[1].decode(errors='replace')
        assert process.returncode == 0, (threads, stderr)
        assert stderr.splitlines() == ['theme-initial:light:light:True:False:False', 'theme-change:dark:dark:True:False:False', 'done'], (threads, stderr)
        assert output.count(ESC + b'[?2031h') == 1 and output.count(ESC + b'[?2031l') == 1, (threads, bytes(output))
        assert termios.tcgetattr(slave) == saved, threads
        print(f'native{threads}: scheme overrides OSC 11, live notification switches theme and restores terminal')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
