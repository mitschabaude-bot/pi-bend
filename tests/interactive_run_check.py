"""Exercise the native editor -> /exit -> terminal-restoration path on a PTY."""
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
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
PROJECT = tempfile.TemporaryDirectory(prefix="pi-bend-interactive-")

for threads, theme in ((1, None), (4, None), (1, "light"), (4, "light")):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    original = termios.tcgetattr(slave)
    args = ["env", f"BEND_THREADS={threads}", str(BINARY), "--no-tools"]
    if theme:
        args += ["--use-theme", theme]
    process = subprocess.Popen(
        args,
        stdin=slave, stdout=slave, stderr=subprocess.PIPE, cwd=PROJECT.name,
        env={**os.environ, "TERM": "xterm-256color", "COLORTERM": "truecolor", "PI_OFFLINE": "1", "PI_CODING_AGENT_DIR": str(Path(PROJECT.name) / "agent")},
    )
    output = bytearray()
    try:
        deadline = time.monotonic() + 30
        expected = b"\x1b[38;2;90;128;128m" if theme == "light" else None
        # A first frame is drawn before startup finishes. Wait for the startup
        # frames to settle before submitting /quit (early submission deliberately
        # retains the draft; startup_input_check.py covers that contract).
        last_output = time.monotonic()
        while time.monotonic() < deadline and (not output or (expected is not None and expected not in output) or time.monotonic() - last_output < 0.5):
            if select.select([master], [], [], 0.2)[0]:
                try:
                    output.extend(os.read(master, 65536))
                    last_output = time.monotonic()
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
        assert output, (threads, process.poll(), process.stderr.read() if process.poll() is not None else b"")
        os.write(master, b"/quit\r")
        stderr = process.communicate(timeout=30)[1]
        while select.select([master], [], [], 0)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
        assert process.returncode == 0, (threads, stderr.decode(errors="replace"), bytes(output))
        assert termios.tcgetattr(slave) == original, threads
        assert b"\x1b[" in output, (threads, bytes(output))
        if expected is not None:
            assert expected in output, (threads, bytes(output))
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
    print(f"native{threads}: {theme or 'default'} theme, mounted, accepted /quit, restored terminal")

PROJECT.cleanup()
