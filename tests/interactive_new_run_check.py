#!/usr/bin/env python3
"""Mounted /new and /clear replace the live session and keep the editor usable."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
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
BINARY = Path(os.environ.get("PI_BEND_NEW_RUN", ROOT / "build/interactive-new-run")).resolve()


def scenario(threads):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-interactive-new-") as place:
        cwd = Path(place)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, str(cwd / "agent")],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=15):
            needles = needle if isinstance(needle, tuple) else (needle,)
            deadline = time.monotonic() + timeout
            while not any(value in output[start:] for value in needles) and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert any(value in output[start:] for value in needles), (threads, needle, process.poll(), bytes(output[start:][-1200:]))

        try:
            until(b"faux-model")
            before = len(output)
            os.write(master, b"before\r")
            until(b'"type":"turn_end"', before)
            for command in (b"/new", b"/clear"):
                before = len(output)
                os.write(master, command + b"\r")
                until(b"New session started", before)
            before = len(output)
            os.write(master, b"hello\r")
            until(b"answer", before)
            os.write(master, b"/exit\r")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, threads
            assert not stderr, (threads, stderr.decode(errors="replace"))
            paths = re.findall(rb'\{"type":"factory","cwd":"[^"]+","sessionFile":"([^"]+)"', output)
            assert len(paths) == 3 and len(set(paths)) == 3, (threads, paths, bytes(output[:1200]))
            assert output.count(b'"reason":"new"') == 2, (threads, bytes(output[:1500]))
            files = list(cwd.glob("*.jsonl"))
            assert len(files) == 2 and {os.fsencode(file) for file in files} == {paths[0], paths[-1]}, (threads, files, paths)
            histories = {os.fsencode(file): [json.loads(line) for line in file.read_text().splitlines()] for file in files}
            assert any(entry.get("type") == "message" and "before" in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
            assert any(entry.get("type") == "message" and "hello" in json.dumps(entry) for entry in histories[paths[-1]]), (threads, histories)
            assert all("hello" not in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: /new, /clear, distinct old/new histories, prompt after replacement, terminal restore")


for threads in (1, 4):
    scenario(threads)
