"""Pinned f07218c4d theme-controller.ts: explicit selection and live auto changes repaint the mounted runner."""
import errno
import fcntl
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
BINARY = Path(os.environ.get("PI_BEND_THEME_RUN", ROOT / "build/interactive-theme-run"))
UPSTREAM = Path("/home/agent/code/pi-mono")
SOURCE = subprocess.check_output(["git", "-C", str(UPSTREAM), "show", "f07218c4d:packages/coding-agent/src/modes/interactive/theme/theme-controller.ts"])
assert b"getThemeSetting()" in SOURCE and b"onTerminalColorSchemeChange" in SOURCE
LIGHT = b"\x1b[38;2;90;128;128m"
DARK = b"\x1b[38;2;138;190;183m"


def scenario(threads, choice, automatic):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-theme-run-") as cwd:
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, cwd + "/agent", choice],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def until(needle):
            deadline = time.monotonic() + 12
            while needle not in output and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            assert needle in output, (threads, choice, needle, process.poll(), bytes(output[-700:]))

        try:
            if automatic:
                until(b"\x1b[?996n")
                until(b"\x1b]11;?\x07")
                os.write(master, b"\x1b[?997;2n\x1b]11;#000000\x07")
            until(LIGHT)
            until(b"theme-fixture")
            if automatic:
                until(b"\x1b[?2031h")
                before = len(output)
                os.write(master, b"\x1b[?997;1n")
                until(DARK)
                assert DARK in output[before:], (threads, bytes(output[before:]))
            os.write(master, b"/exit\r")
            stderr = process.communicate(timeout=12)[1]
            assert process.returncode == 0, (threads, choice, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, threads
            if automatic:
                until(b"\x1b[?2031l")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)


for threads in (1, 4):
    scenario(threads, "light", False)
    scenario(threads, "light/dark", True)
    print(f"native{threads}: explicit light and automatic light→dark repaint the actual editor frame")
