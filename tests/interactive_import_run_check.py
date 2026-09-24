#!/usr/bin/env python3
"""Mounted /import confirms, copies, rebinds, and handles a missing stored cwd."""
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
BINARY = Path(os.environ.get("PI_BEND_IMPORT_RUN", ROOT / "build/interactive-import-run"))
SOURCE = ROOT / "tests/fixtures/export-input.jsonl"

for threads in (1, 4):
    with tempfile.TemporaryDirectory(prefix="pi-interactive-import-") as place:
        cwd = Path(place)
        external = cwd / "external"
        external.mkdir()
        records = [json.loads(line) for line in SOURCE.read_text().splitlines()]
        records[0]["cwd"] = str(cwd)
        source = external / "import.jsonl"
        source.write_text("\n".join(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) for entry in records) + "\n")
        missing = external / "missing-cwd.jsonl"
        records[0]["cwd"] = str(cwd / "gone")
        missing.write_text("\n".join(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) for entry in records) + "\n")
        (external / "broken.jsonl").write_text("{not json}\n")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 140, 0, 0))
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

        def command(text, expected):
            start = len(output)
            os.write(master, text + b"\r")
            until(expected, start)

        def until_file(path, timeout=20):
            deadline = time.monotonic() + timeout
            while not path.exists() and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    output.extend(os.read(master, 65536))
            assert path.exists(), (threads, path, process.poll(), list(cwd.glob("*.jsonl")), bytes(output[-1200:]))

        try:
            until(b"faux-model")
            command(b"/import", b"Usage: /import <path.jsonl>")
            command(b"/import external/import.jsonl", b"Replace current session")
            os.write(master, b"2")
            until(b"Import cancelled")
            assert not (cwd / "import.jsonl").exists()
            command(b"/import external/import.jsonl", b"Replace current session")
            os.write(master, b"1")
            until(b"Session imported from: external/import.jsonl")
            imported = cwd / "import.jsonl"
            assert imported.read_bytes() == source.read_bytes()
            command(b"after import", b"answer")
            command(b"/import external/import.jsonl", b"Replace current session")
            os.write(master, b"1")
            until_file(cwd / "import-1.jsonl")
            assert (cwd / "import-1.jsonl").read_bytes() == source.read_bytes()
            command(b"/import external/missing-cwd.jsonl", b"Replace current session")
            os.write(master, b"1")
            until(b"Session cwd not found")
            os.write(master, b"1")
            until_file(cwd / "missing-cwd.jsonl")
            command(b"/import external/broken.jsonl", b"Replace current session")
            os.write(master, b"1")
            until(b"Failed to import session:")
            assert not (cwd / "broken.jsonl").exists()
            command(b"/import external/absent.jsonl", b"Replace current session")
            os.write(master, b"1")
            until(b"File not found: external/absent.jsonl")
            os.write(master, b"/exit\r")
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
    print(f"native{threads}: confirmed import, cancel, unique copy, cwd fallback, continued prompt, terminal restore")
