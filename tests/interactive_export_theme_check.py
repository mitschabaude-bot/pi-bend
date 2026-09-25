"""An interactive /export uses the active theme, including a missing-theme fallback."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli")).resolve()


def scenario(requested, expected):
    with tempfile.TemporaryDirectory(prefix="pi-export-theme-") as directory:
        project = Path(directory)
        session = project / "session.jsonl"
        output_file = project / "export.html"
        shutil.copyfile(ROOT / "tests/fixtures/export-input.jsonl", session)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        process = subprocess.Popen(
            [str(BINARY), "--no-tools", "--use-theme", requested, "--session", str(session)],
            cwd=project, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color", "BEND_THREADS": "1"},
        )
        screen = bytearray()

        def pump():
            if select.select([master], [], [], 0.1)[0]:
                try:
                    screen.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise

        try:
            deadline = time.monotonic() + 30
            while b"\x1b[?2026l" not in screen and time.monotonic() < deadline and process.poll() is None:
                pump()
            assert b"\x1b[?2026l" in screen, (requested, process.poll(), bytes(screen[-1000:]))
            os.write(master, ("/export " + str(output_file) + "\r").encode())
            deadline = time.monotonic() + 25
            while (not output_file.exists() or b"</html>" not in output_file.read_bytes()) and time.monotonic() < deadline and process.poll() is None:
                pump()
            assert output_file.exists(), (requested, process.poll(), bytes(screen[-1000:]))
            html = output_file.read_text()
            for color in expected:
                assert color in html, (requested, color)
            os.write(master, b"/quit\r")
            _, stderr = process.communicate(timeout=15)
            assert process.returncode == 0, (requested, stderr)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"interactive /export: {requested} -> {expected[0]}")


scenario("light", ("--body-bg: #f8f8f8;", "--text: #1f2328;", "--exportInfoBg: #fffae6;"))
scenario("missing-theme", ("--body-bg: #18181e;", "--text: #d4d4d4;", "--exportInfoBg: #3c3728;"))
