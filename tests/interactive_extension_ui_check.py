#!/usr/bin/env python3
"""Exercise an inline Bend extension command through the mounted terminal UI.

Run with: uv run --with pyte tests/interactive_extension_ui_check.py
"""
import errno
import codecs
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

import pyte

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
        screen = pyte.Screen(100, 24)
        terminal = pyte.Stream(screen)
        decoder = codecs.getincrementaldecoder("utf-8")("replace")

        def until(needle: bytes, start: int = 0, timeout: float = 15) -> None:
            deadline = time.monotonic() + timeout
            while needle not in output[start:] and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        chunk = os.read(master, 65536)
                        output.extend(chunk)
                        terminal.feed(decoder.decode(chunk))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            plain = re.sub(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)", b"", output[start:])
            assert needle in output[start:], (threads, needle, process.poll(), plain[-3000:], screen.display)

        try:
            until(b"faux-model")
            time.sleep(.5)
            start = len(output)
            os.write(master, b"/ask\r")
            until(b"Pick a value", start)
            until(b"beta", start)
            os.write(master, b"\x0f")
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
            os.write(master, b"/ask-aborted\r")
            until(b"Pre-aborted prompt cancelled", start)
            assert b"Should not open" not in output[start:], output[start:][-1000:]
            start = len(output)
            os.write(master, b"/ask-timeout\r")
            until(b"Timed choice (1s)", start)
            until(b"Timed prompt cancelled", start, timeout=4)
            time.sleep(.3)
            start = len(output)
            os.write(master, b"/ask-abort-later\r")
            until(b"Aborting input", start)
            until(b"Active prompt aborted", start, timeout=4)
            start = len(output)
            os.write(master, b"/ask-input\r")
            until(b"Name a value", start)
            os.write(master, b"after-timeout\r")
            until(b"Extension chose: after-timeout", start)
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
            start = len(output)
            os.write(master, b"/show-widget\r")
            until(b"fixture widget above", start)
            until(b"fixture widget below", start)
            assert all(any(label in row for row in screen.display) for label in ("fixture widget above", "fixture widget below")), screen.display
            start = len(output)
            os.write(master, b"/working-style\r")
            until(b"Working configured", start)
            start = len(output)
            os.write(master, b"/new\r")
            until(b"New session started", start)
            assert all(label not in row for row in screen.display for label in ("fixture widget above", "fixture widget below")), screen.display
            start = len(output)
            os.write(master, b"/show-widget\r")
            until(b"fixture widget above", start)
            until(b"fixture widget below", start)
            start = len(output)
            os.write(master, b"/ask\r")
            until(b"Pick a value", start)
            os.write(master, b"\x1b")
            until(b"Extension prompt cancelled", start)
            start = len(output)
            os.write(master, b"before-style\r")
            until(b"Working", start)
            until(b"answer", start)
            assert b"Fixture working" not in output[start:], output[start:][-1000:]
            start = len(output)
            os.write(master, b"/working-style\r")
            until(b"Working configured", start)
            start = len(output)
            os.write(master, b"first\r")
            until("◆".encode(), start)
            until(b"Fixture working", start)
            until(b"again", start)
            start = len(output)
            os.write(master, b"/working-hide\r")
            until(b"Working configured", start)
            start = len(output)
            os.write(master, b"second\r")
            until(b"hidden reply", start)
            assert b"Fixture working" not in output[start:], output[start:][-1000:]
            start = len(output)
            os.write(master, b"/working-reset\r")
            until(b"Working configured", start)
            start = len(output)
            os.write(master, b"third\r")
            until(b"Working", start)
            until(b"(no scripted response)", start)
            assert b"Fixture working" not in output[start:], output[start:][-1000:]
            os.write(master, b"/quit\r")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0 and not stderr, (process.returncode, stderr)
            assert termios.tcgetattr(slave) == original, threads
            print(f"native{threads}: extension prompts, timeout/abort, widgets, Working controls, session reset and terminal restoration")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)


for count in (1, 4):
    scenario(count)
