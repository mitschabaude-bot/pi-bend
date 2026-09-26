"""Exercise live TUI preference changes from input callbacks through a real PTY."""
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
BINARY = Path(os.environ.get("PI_BEND_TUI_PREFERENCES", ROOT / "build/tui-live-preferences")).resolve()
for threads in (1, 4):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    original = termios.tcgetattr(slave)
    process = subprocess.Popen([str(BINARY), "--threads", str(threads)], cwd=ROOT,
                               stdin=slave, stdout=slave, stderr=subprocess.PIPE,
                               env={**os.environ, "TERM": "xterm-256color"})
    output = bytearray()
    def until(needle, start=0):
        deadline = time.monotonic() + 8
        while needle not in output[start:] and time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
        assert needle in output[start:], (threads, needle, bytes(output[start:]), process.poll())
    try:
        until(b"live preferences")
        at = len(output)
        os.write(master, b"b")
        until(b"\x1b[?25h", at)
        at = len(output)
        os.write(master, b"h")
        until(b"\x1b[?25lhide-returned", at)
        at = len(output)
        os.write(master, b"b")
        until(b"\x1b[?25h", at)
        os.write(master, b"c")
        time.sleep(.1)
        os.write(master, b"q")
        stderr = process.communicate(timeout=8)[1].decode()
        assert process.returncode == 0, (threads, stderr)
        assert stderr.splitlines() == ["ready", "changed", "changed", "preferences:cursor=true,clear=false"], stderr
        assert termios.tcgetattr(slave) == original, threads
        print(f"native{threads}: live cursor visibility, coalesced updates, independent preferences and clean shutdown")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
