#!/usr/bin/env python3
"""Pinned interactive command routing through the mounted native editor and PTY."""
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
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
BINARY = Path(os.environ.get("PI_BEND_COMMAND_RUN", ROOT / "build/interactive-commands-run")).resolve()


def scenario(threads):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 200, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-commands-run-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent", "dark"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=12):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-800:]))

        try:
            until(b"theme-fixture")
            cases = [
                ("/help", b"Commands: /model [search], /thinking [level], /compact [instructions], /new, /clear, /name [name], /login, /logout, /export [path], /import <path>, /resume, /tree, /fork, /exit"),
                ("/thinking", b"Thinking level: off. Available: off"),
                ("/thinking OFF", b"Thinking level: off"),
                ("/thinking medium", b'Unknown thinking level "medium". Available levels: off.'),
                ("/compact", b"Error: Nothing to compact (session too small)"),
                ("/name", b"Usage: /name <name>"),
                ("/name Midnight Session", b"Session name set: Midnight Session"),
                ("/name", b"Session name: Midnight Session"),
                ("/logout", b"Logout is available in interactive mode only"),
                ("/new", b"Starting a new session is not available yet"),
                ("/clear", b"Starting a new session is not available yet"),
                ("/unknown", b"Unknown command: /unknown"),
                ("!echo hi", b"Unknown command: !echo hi"),
            ]
            for command, expected in cases:
                before = len(output)
                os.write(master, command.encode() + b"\r")
                until(expected, before)
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
    print(f"native{threads}: built-in command results, unsupported errors, next input, and terminal restore")


for threads in (1, 4):
    scenario(threads)
