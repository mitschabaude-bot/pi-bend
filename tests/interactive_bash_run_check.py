#!/usr/bin/env python3
"""Interactive native Bash streams, records context choice, and remains usable."""
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
BINARY = Path(os.environ.get("PI_BEND_BASH_RUN", ROOT / "build/interactive-bash-run"))


def nested(value, name):
    if isinstance(value, dict):
        if value.get("command") == name:
            return value
        for child in value.values():
            found = nested(child, name)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = nested(child, name)
            if found is not None:
                return found
    return None


def scenario(threads):
    with tempfile.TemporaryDirectory(prefix="pi-bash-run-") as place:
        cwd = Path(place)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 160, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, str(cwd / "agent")],
            cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=25):
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

        def command(source, expected):
            start = len(output)
            os.write(master, source + b"\r")
            until(expected, start)

        def recorded(name, timeout=20):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                command(b"/export snapshot.jsonl", b"Session exported to:")
                for line in (cwd / "snapshot.jsonl").read_text().splitlines():
                    found = nested(json.loads(line), name)
                    if found is not None:
                        return found
                time.sleep(.2)
            raise AssertionError((threads, "not recorded", name, bytes(output[-1000:])))

        try:
            until(b"faux-model")
            command(b"!printf VISIBLE_BASH", b"$ printf VISIBLE_BASH")
            visible = recorded("printf VISIBLE_BASH")
            command(b"!!printf HIDDEN_BASH", b"$ printf HIDDEN_BASH")
            hidden = recorded("printf HIDDEN_BASH")
            command(b"!false", b"$ false")
            failed = recorded("false")
            assert b"(exit 1)" in output
            start = len(output)
            os.write(master, b"!sleep 5\r")
            until(b"Running...", start)
            start = len(output)
            os.write(master, b"\x1b")
            until(b"(cancelled)", start)
            recorded("sleep 5")
            command(b"/export bash.jsonl", b"Session exported to:")
            records = [json.loads(line) for line in (cwd / "bash.jsonl").read_text().splitlines()]
            assert all(any(nested(record, name) is not None for record in records) for name in ("printf VISIBLE_BASH", "printf HIDDEN_BASH", "false", "sleep 5"))
            assert visible["output"] == "VISIBLE_BASH" and visible.get("excludeFromContext") is False, visible
            assert hidden["output"] == "HIDDEN_BASH" and hidden.get("excludeFromContext") is True, hidden
            assert failed["exitCode"] == 1, failed
            command(b"/import snapshot.jsonl", b"Replace current session")
            start = len(output)
            os.write(master, b"1")
            until(b"$ printf HIDDEN_BASH", start)
            until(b"Session imported from: snapshot.jsonl", start)
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
    print(f"native{threads}: Bash output, status, context exclusion, persisted history, terminal restore")


for threads in (1, 4):
    scenario(threads)
