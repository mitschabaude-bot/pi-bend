"""A restored session paints structural messages and expands its summaries."""
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
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli")).resolve()

with tempfile.TemporaryDirectory(prefix="pi-resumed-messages-") as directory:
    project = Path(directory)
    session = project / "session.jsonl"
    stamp = "2026-01-01T00:00:00.000Z"
    entries = [
        {"type": "session", "version": 3, "id": "structural", "timestamp": stamp, "cwd": str(project)},
        {"type": "message", "id": "u1", "parentId": None, "timestamp": stamp, "message": {"role": "user", "content": "original prompt", "timestamp": 1}},
        {"type": "compaction", "id": "c1", "parentId": "u1", "timestamp": stamp, "summary": "Earlier plan", "firstKeptEntryId": "u1", "tokensBefore": 1200},
        {"type": "branch_summary", "id": "b1", "parentId": "c1", "timestamp": stamp, "fromId": "u1", "summary": "Alternative path"},
        {"type": "custom_message", "id": "m1", "parentId": "b1", "timestamp": stamp, "customType": "notice", "content": "Visible extension note", "display": True},
        {"type": "custom_message", "id": "m2", "parentId": "m1", "timestamp": stamp, "customType": "private", "content": "Hidden extension note", "display": False},
        {"type": "message", "id": "u2", "parentId": "m2", "timestamp": stamp, "message": {"role": "user", "content": '<skill name="example-skill" location="/tmp/example-skill.md">\nskill details\n</skill>\n\nPlease proceed', "timestamp": 2}},
    ]
    session.write_text("\n".join(json.dumps(entry, separators=(",", ":")) for entry in entries) + "\n")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
    process = subprocess.Popen(
        [str(BINARY), "--no-tools", "--session", str(session)], cwd=project,
        stdin=slave, stdout=slave, stderr=subprocess.PIPE,
        env={**os.environ, "TERM": "xterm-256color", "BEND_THREADS": "1"},
    )
    screen = bytearray()

    def until(needle, start=0, timeout=25):
        deadline = time.monotonic() + timeout
        while needle not in screen[start:] and time.monotonic() < deadline and process.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    screen.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
        assert needle in screen[start:], (needle, process.poll(), bytes(screen[-1500:]))

    try:
        until(b"[compaction]")
        until(b"[branch]")
        until(b"Visible extension note")
        until(b"[skill]")
        until(b"Please proceed")
        before = bytes(screen)
        assert b"Earlier plan" not in before and b"Alternative path" not in before
        assert b"Hidden extension note" not in before
        assert b"<skill" not in before and b"skill details" not in before
        start = len(screen)
        os.write(master, b"\x0f")
        until(b"Earlier plan", start)
        until(b"Alternative path", start)
        until(b"skill details", start)
        os.write(master, b"/quit\r")
        _, stderr = process.communicate(timeout=15)
        assert process.returncode == 0, stderr
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
print("resumed summaries, custom messages and skill invocations render in order")
