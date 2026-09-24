#!/usr/bin/env python3
"""Interactive /resume reuses the native picker and switches the live session."""
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
BINARY = Path(os.environ.get("PI_BEND_RESUME_RUN", ROOT / "build/interactive-resume-run"))
SOURCE = ROOT / "tests/fixtures/export-input.jsonl"


def write_session(path, cwd, name):
    records = [json.loads(line) for line in SOURCE.read_text().splitlines()]
    records[0]["cwd"] = str(cwd)
    records[0]["id"] = name.lower()
    records[1]["message"]["content"] = name + " RESUME SESSION"
    path.write_text("\n".join(json.dumps(record, ensure_ascii=False, separators=(",", ":")) for record in records) + "\n")


for threads in (1, 4):
    with tempfile.TemporaryDirectory(prefix="pi-interactive-resume-") as place:
        cwd = Path(place)
        target = cwd / "target.jsonl"
        missing = cwd / "missing.jsonl"
        write_session(target, cwd, "TARGET")
        write_session(missing, cwd / "gone", "MISSING")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 150, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, str(cwd / "agent")],
            cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=20):
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-1200:]))

        def command(data, expected):
            start = len(output)
            os.write(master, data + b"\r")
            until(expected, start)

        try:
            until(b"faux-model")
            command(b"/resume", b"Resume Session (Current Folder)")
            before = len(output)
            os.write(master, b"\x1b")
            until(b"\x1b[7m", before)
            command(b"/resume", b"Resume Session (Current Folder)")
            os.write(master, b"TARGET")
            until(b"TARGET RESUME SESSION")
            os.write(master, b"\r")
            until(b"Resumed session")
            command(b"after resume", b"answer")
            command(b"/export active.jsonl", b"Session exported to:")
            exported = (cwd / "active.jsonl").read_text()
            assert "TARGET RESUME SESSION" in exported and "after resume" in exported
            command(b"/resume", b"Resume Session (Current Folder)")
            before = len(output)
            os.write(master, b"\t")
            until(b"Resume Session (All)", before)
            os.write(master, b"MISSING")
            until(b"MISSING RESUME SESSION")
            os.write(master, b"\r")
            until(b"Session cwd not found")
            before = len(output)
            os.write(master, b"1")
            until(b"Resumed session", before)
            command(b"after fallback", b"answer")
            command(b"/export fallback.jsonl", b"Session exported to:")
            fallback = (cwd / "fallback.jsonl").read_text()
            assert "MISSING RESUME SESSION" in fallback and "after fallback" in fallback
            os.write(master, b"/quit\r")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original
            assert not stderr, stderr.decode(errors="replace")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: picker cancel/search, resume/rebind, cwd fallback, terminal restore")
