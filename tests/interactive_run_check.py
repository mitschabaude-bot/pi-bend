"""Exercise the native editor -> /exit -> terminal-restoration path on a PTY."""
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
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))

for threads in (1, 4):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    original = termios.tcgetattr(slave)
    process = subprocess.Popen(
        [str(BINARY), "--threads", str(threads), "--", "--no-tools"],
        stdin=slave, stdout=slave, stderr=subprocess.PIPE, cwd=ROOT,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    output = bytearray()
    try:
        deadline = time.monotonic() + 30
        while not output and time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
        assert output, (threads, process.poll(), process.stderr.read() if process.poll() is not None else b"")
        os.write(master, b"/exit\r")
        stderr = process.communicate(timeout=30)[1]
        assert process.returncode == 0, (threads, stderr.decode(errors="replace"), bytes(output))
        assert termios.tcgetattr(slave) == original, threads
        assert b"\x1b[" in output, (threads, bytes(output))
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
    print(f"native{threads}: mounted, accepted /exit, restored terminal")
