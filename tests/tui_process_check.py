"""Exercise native TUI frame planning and terminal writes through a real PTY."""
import errno
import fcntl
import os
import pty
import struct
import subprocess
import termios

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
process = subprocess.Popen(
    ["build/tui-process"], stdin=slave, stdout=slave, stderr=subprocess.PIPE,
    env={**os.environ, "TERM": "xterm-256color"},
)
os.close(slave)
try:
    stderr = process.communicate(timeout=20)[1]
    output = bytearray()
    while True:
        try:
            chunk = os.read(master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        output.extend(chunk)
finally:
    os.close(master)
assert process.returncode == 0, stderr.decode(errors="replace")
assert output.find(b"hello") >= 0, output
assert output.find(b"world") > output.find(b"hello"), output
assert b"two TUI frames committed" in stderr, stderr
print("native owner → planner → PTY writes two committed frames")
