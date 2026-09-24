#!/usr/bin/env python3
"""Mounted startup header and Ctrl+O expansion, pinned to pi's InteractiveMode.initialize()."""
import errno
import fcntl
import hashlib
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
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
BINARY = Path(os.environ.get("PI_BEND_HEADER_RUN", ROOT / "build/header-run")).resolve()


def scenario(threads, quiet):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 110, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-header-run-") as cwd:
        agent_dir = Path(cwd) / "agent"
        agent_dir.mkdir()
        if quiet:
            (agent_dir / "settings.json").write_text(json.dumps({"quietStartup": True}))
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, str(agent_dir), "dark"],
            stdin=slave, stdout=slave, stderr=subprocess.PIPE, cwd=ROOT,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=8):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, quiet, needle, process.poll(), bytes(output[-900:]))

        try:
            until(b"theme-fixture")
            if quiet:
                assert b"escape interrupt" not in output, (threads, bytes(output[-900:]))
            else:
                until(b"escape interrupt")
                assert b"Pi can explain its own features" in output
                start = len(output)
                os.write(master, b"\x0f")
                until(b"ctrl+c  clear", start)
            os.write(master, b"/quit\r")
            stderr = process.communicate(timeout=10)[1]
            assert process.returncode == 0 and not stderr, (process.returncode, stderr)
            assert termios.tcgetattr(slave) == original, threads
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: {'quiet' if quiet else 'compact/expanded'} startup header, terminal restored")


for threads in (1, 4):
    for quiet in (False, True):
        scenario(threads, quiet)
