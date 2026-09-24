#!/usr/bin/env python3
"""Slash /tree and /fork use the mounted session selector and session controller."""
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
BINARY = Path(os.environ.get("PI_BEND_TREE_COMMAND_RUN", ROOT / "build/interactive-tree-run"))


def scenario(threads, command):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-tree-command-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=15):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, command, needle, process.poll(), bytes(output[start:][-1400:]))

        try:
            until(b"faux-model")
            start = len(output)
            os.write(master, b"first\r")
            until(b'"type":"turn_end"', start)
            start = len(output)
            os.write(master, command + b"\r")
            until(b"Session Tree" if command == b"/tree" else b"Fork from Message", start)
            assert b"user: first" in output[start:]
            if command == b"/tree":
                assert b"assistant: answer" in output[start:]
                os.write(master, b"\x1b[A")
            start = len(output)
            os.write(master, b"\r")
            until(b"first\x1b[7m", start)
            os.write(master, b"\x03\x03")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0, (threads, command, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original
            assert not stderr, stderr.decode(errors="replace")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: {command.decode()} opens selector, selects user entry, restores terminal")


for threads in (1, 4):
    for command in (b"/tree", b"/fork"):
        scenario(threads, command)
