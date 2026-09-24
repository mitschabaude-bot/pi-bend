#!/usr/bin/env python3
"""Ctrl+O expands existing Bash output and applies to subsequent commands."""
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
BINARY = Path(os.environ.get("PI_BEND_EXPAND_RUN", ROOT / "build/interactive-expand-run"))


def scenario(threads):
    with tempfile.TemporaryDirectory(prefix="pi-expand-run-") as place:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 100, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, place + "/agent"],
            cwd=place, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=30):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-1800:]))

        def drain(seconds):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    output.extend(os.read(master, 65536))

        try:
            until(b"faux-model")
            start = len(output)
            os.write(master, b"!seq -f X%02g 1 25\r")
            until(b"$ seq -f X%02g 1 25", start)
            until(b"X25", start)
            drain(1)
            start = len(output)
            os.write(master, b"\x0f")
            until(b"X01", start)
            until(b"Tool output: expanded", start)
            start = len(output)
            os.write(master, b"!seq -f Y%02g 1 25\r")
            until(b"$ seq -f Y%02g 1 25", start)
            until(b"Y01", start)
            drain(1)
            start = len(output)
            os.write(master, b"\x0f")
            until(b"Tool output: collapsed", start)
            os.write(master, b"/exit\r")
            deadline = time.monotonic() + 20
            while process.poll() is None and time.monotonic() < deadline:
                drain(.1)
            assert process.poll() == 0, (threads, process.poll())
            assert termios.tcgetattr(slave) == original
            assert not process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: Ctrl+O expands existing and future Bash output, then collapses")


for threads in (1, 4):
    scenario(threads)
