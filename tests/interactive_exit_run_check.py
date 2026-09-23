#!/usr/bin/env python3
"""Mounted Ctrl+D behavior pinned to pi f07218c4d CustomEditor.handleInput."""
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
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/components/custom-editor.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "a19deef137c3c653e24372842dd49bb819f8fcc24a69a5dc6ec60fc2bad3f8f1"
BINARY = Path(os.environ.get("PI_BEND_EXIT_RUN", ROOT / "build/interactive-navigation-fixture")).resolve()


def check(threads, draft):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-exit-run-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent", "dark"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, timeout=15):
            deadline = time.monotonic() + timeout
            while needle not in output and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
            assert needle in output, (threads, needle, process.poll(), bytes(output[-1000:]))

        try:
            until(b"theme-fixture")
            if draft:
                os.write(master, b"unsent draft\x04")
                time.sleep(.4)
                assert process.poll() is None, (threads, "Ctrl+D exited with a draft")
                assert b"fixture-prompt-started" not in output
                os.write(master, b"\x03")
                time.sleep(.1)
            os.write(master, b"\x04")
            stderr = process.communicate(timeout=15)[1]
            assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, threads
            assert not stderr, (threads, stderr.decode(errors="replace"))
            assert b"fixture-prompt-started" not in output
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: Ctrl+D {'preserves nonempty draft then ' if draft else ''}exits and restores terminal")


for threads in (1, 4):
    check(threads, False)
    check(threads, True)
