#!/usr/bin/env python3
"""Exercise an inline Bend extension command through the mounted terminal UI."""
import errno
import fcntl
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
BINARY = Path(os.environ.get("PI_BEND_EXTENSION_UI_RUN", ROOT / "build/interactive-new-run")).resolve()


def scenario(threads: int) -> None:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-extension-ui-") as place:
        root = Path(place)
        agent_dir = root / "agent"
        agent_dir.mkdir()
        editor = root / "extension-editor.py"
        editor.write_text('import pathlib, sys\npathlib.Path(sys.argv[-1]).write_text("seed-external\\n")\n')
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", "ui", str(ROOT), place, str(agent_dir)],
            cwd=root, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "PI_FAUX_API_KEY": "faux-key", "TERM": "xterm-256color", "DISPLAY": "", "WAYLAND_DISPLAY": "", "TERMUX_VERSION": "", "PI_TUI_ESC_TIMEOUT": "10", "VISUAL": f"python3 {editor}"},
        )
        output = bytearray()

        def until(needle: bytes, start: int = 0, timeout: float = 15) -> None:
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            plain = re.sub(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)", b"", output[start:])
            assert needle in output[start:], (threads, needle, process.poll(), plain[-3000:])

        try:
            until(b"faux-model")
            time.sleep(.5)
            start = len(output)
            os.write(master, b"/ask\r")
            until(b"Pick a value", start)
            until(b"beta", start)
            os.write(master, b"\x1b[B\r")
            until(b"Extension chose: beta", start)
            start = len(output)
            os.write(master, b"/ask\r")
            until(b"Pick a value", start)
            os.write(master, b"\x1b")
            until(b"Extension prompt cancelled", start)
            start = len(output)
            os.write(master, b"/ask-input\r")
            until(b"Name a value", start)
            os.write(master, b"hello\r")
            until(b"Extension chose: hello", start)
            start = len(output)
            os.write(master, b"/ask-editor\r")
            until(b"Write a note", start)
            os.write(master, b"\r")
            until(b"Extension chose: seed", start)
            start = len(output)
            os.write(master, b"/ask-editor\r")
            until(b"Write a note", start)
            os.write(master, b"\x07")
            until(b"seed-external", start)
            os.write(master, b"\r")
            until(b"Extension chose: seed-external", start)
            os.write(master, b"/quit\r")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0 and not stderr, (process.returncode, stderr)
            assert termios.tcgetattr(slave) == original, threads
            print(f"native{threads}: extension prompts, external editor, cancellation and terminal restoration")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)


for count in (1, 4):
    scenario(count)
