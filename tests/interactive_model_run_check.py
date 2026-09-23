#!/usr/bin/env python3
"""Mounted model switching against pinned pi interactive model behavior."""
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
UPSTREAM = Path(os.environ.get("PI_MONO", COMMON.parent.parent / "pi-mono"))
SOURCES = {
    "packages/coding-agent/src/modes/interactive/interactive-mode.ts": "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388",
    "packages/coding-agent/src/modes/interactive/components/model-selector.ts": "92d70b9faffc9febf2ce0c519c7c086938bddfc5da9ad28d819f408d54e3637e",
    "packages/coding-agent/src/modes/interactive/model-search.ts": "9be620174c0f25516b0c537dcd4ef9be7c9c9a145e6489e186cc6c4787b25412",
}
for path, digest in SOURCES.items():
    assert hashlib.sha256((UPSTREAM / path).read_bytes()).hexdigest() == digest, path
BINARY = Path(os.environ.get("PI_BEND_MODEL_RUN", ROOT / "build/model-run-native")).resolve()


def scenario(threads):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-model-run-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent", "dark"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=12):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .15)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-1200:]))

        try:
            until(b"theme-fixture")
            at = len(output)
            os.write(master, b"/model\r")
            until(b"Select Model", at)
            until(b"fixture/alternate", at)
            at = len(output)
            os.write(master, b"alternate")
            until(b"Search:", at)
            until(b"alternate", at)
            os.write(master, b"\r")
            until(b"Model: fixture/alternate", at)
            at = len(output)
            os.write(master, b"/model fixture/theme-fixture\r")
            until(b"Model: fixture/theme-fixture", at)
            at = len(output)
            os.write(master, b"/model absent\r")
            until(b"No matching models", at)
            os.write(master, b"\x1b")
            time.sleep(.3)  # Give the terminal parser time to resolve a lone Escape.
            at = len(output)
            os.write(master, b"/help\r")
            until(b"Commands: /model [search]", at)
            os.write(master, b"/exit\r")
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
    print(f"native{threads}: picker, fuzzy search, exact switch, cancellation, next command, terminal restore")


for threads in (1, 4):
    scenario(threads)
