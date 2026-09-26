#!/usr/bin/env python3
"""Mounted key lifecycle against pi f07218c4d interactive-mode.ts."""
from upstream_pin import UPSTREAM
import errno
import fcntl
import hashlib
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
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
KEYBINDINGS = UPSTREAM / "packages/coding-agent/src/core/keybindings.ts"
assert hashlib.sha256(KEYBINDINGS.read_bytes()).hexdigest() == "38e8b20700e40452acab4c9583d96d9c304bbe15c471e214e50b65ec3b3f1945"
BINARY = Path(os.environ.get("PI_BEND_INTERRUPT_RUN", ROOT / "build/interactive-interrupt-fixture")).resolve()


def scenario(threads, queued_key, queued_text, restore_key):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-interrupt-run-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent", "dark"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color", "PI_FAUX_API_KEY": "faux-key"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=12):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-1000:]))

        def drain():
            while select.select([master], [], [], 0)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break

        try:
            until(b"theme-fixture")
            idle_start = len(output)
            os.write(master, b"\x1b")
            time.sleep(.3)
            drain()
            assert b"No queued messages to restore" not in output[idle_start:], threads
            os.write(master, b"first\r")
            until(b"fixture-prompt-started")
            before = len(output)
            os.write(master, queued_text + queued_key)
            if restore_key == b"\x1b":
                os.write(master, b"\x1b")
            else:
                os.write(master, restore_key)
            until(b"Restored 1 queued message to editor", before)
            until(queued_text, before)
            time.sleep(2.1)
            drain()
            assert output.count(b"fixture-prompt-started") == 1, (threads, output.count(b"fixture-prompt-started"))
            if restore_key == b"\x1b":
                assert b"late-response" not in output, (threads, bytes(output[-1000:]))
            else:
                assert b"late-response" in output, (threads, bytes(output[-1000:]))
            os.write(master, b"\x03\x03")  # Clear, then exit within 500 ms.
            stderr = process.communicate(timeout=15)[1]
            assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, threads
            assert not stderr, (threads, stderr.decode(errors="replace"))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: {restore_key!r} restored queued input with expected abort/completion and terminal cleanup")


for threads in (1, 4):
    scenario(threads, b"\r", b"steer one", b"\x1b")
    scenario(threads, b"\x1b\r", b"follow one", b"\x1b[1;3A")
