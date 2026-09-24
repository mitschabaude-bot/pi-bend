#!/usr/bin/env python3
"""Ctrl+T changes and persists thinking visibility in the native terminal."""
import errno
import fcntl
import json
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
BINARY = Path(os.environ.get("PI_BEND_THINKING_RUN", ROOT / "build/interactive-thinking-run"))


def scenario(threads):
    with tempfile.TemporaryDirectory(prefix="pi-thinking-run-") as place:
        settings = Path(place) / "agent" / "settings.json"
        settings.parent.mkdir()
        settings.write_text('{"hideThinkingBlock":true}\n')
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, place + "/agent"],
            cwd=place, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0):
            deadline = time.monotonic() + 20
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[-1200:]))

        try:
            until(b"faux-model")
            for expected, persisted in ((b"Thinking blocks: visible", False), (b"Thinking blocks: hidden", True)):
                start = len(output)
                os.write(master, b"\x14")
                until(expected, start)
                assert json.loads(settings.read_text())["hideThinkingBlock"] is persisted
            os.write(master, b"/quit\r")
            deadline = time.monotonic() + 20
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert process.poll() == 0, (threads, process.poll(), bytes(output[-1200:]))
            assert termios.tcgetattr(slave) == original
            assert not process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: Ctrl+T toggles and persists thinking visibility")


for threads in (1, 4):
    scenario(threads)
