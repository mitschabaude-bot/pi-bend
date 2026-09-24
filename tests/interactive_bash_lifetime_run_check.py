#!/usr/bin/env python3
"""Overlapping Bash submissions and terminal exit preserve task ownership."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_BASH_LIFETIME_RUN", ROOT / "build/interactive-bash-lifetime-run"))


def scenario(threads, exit_during_bash):
    with tempfile.TemporaryDirectory(prefix="pi-bash-lifetime-") as place:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, place + "/agent"],
            cwd=place, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def read_for(seconds):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break

        def until(needle, start=0, timeout=15):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                read_for(.1)
            assert needle in output[start:], (threads, exit_during_bash, needle, process.poll(), bytes(output[start:][-1000:]))

        try:
            until(b"faux-model")
            start = len(output)
            if exit_during_bash:
                os.write(master, b"!sleep 5\r")
                until(b"Running...", start)
                os.write(master, b"/exit\r")
            else:
                os.write(master, b"!sleep 5\r!printf SECOND_BASH\r")
                until(b"A bash command is already running", start)
                until(b"!printf SECOND_BASH", start)
                read_for(.2)
                os.write(master, b"\x1b")
                until(b"(cancelled)", start)
                start = len(output)
                os.write(master, b"\r")
                until(b"$ printf SECOND_BASH", start)
                os.write(master, b"/exit\r")
            deadline = time.monotonic() + 12
            while process.poll() is None and time.monotonic() < deadline:
                read_for(.1)
            assert process.poll() == 0, (threads, exit_during_bash, process.poll(), bytes(output[-1200:]))
            assert termios.tcgetattr(slave) == original
            assert not process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: {'exit cancels active Bash' if exit_during_bash else 'overlap rejected and draft restored'}")


for threads in (1, 4):
    scenario(threads, False)
    scenario(threads, True)
