#!/usr/bin/env python3
"""Exercise the mounted config selector and persisted global/project resource overrides."""
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
BINARY = Path(os.environ.get("PI_BEND_CONFIG_RUN", ROOT / "build/pi-config-candidate")).resolve()


def run(threads):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 28, 110, 0, 0))
    with tempfile.TemporaryDirectory(prefix="pi-config-") as location:
        cwd = Path(location)
        agent_dir = cwd / "agent"
        extension_dir = agent_dir / "extensions"
        extension_dir.mkdir(parents=True)
        (extension_dir / "sample.bend").write_text("import Base\n")
        process = subprocess.Popen(
            [str(BINARY), "config", "-a"], cwd=cwd, stdin=slave, stdout=slave,
            stderr=subprocess.PIPE,
            env={**os.environ, "PI_CODING_AGENT_DIR": str(agent_dir), "PI_BEND_PACKAGE_DIR": str(ROOT),
                 "BEND_THREADS": str(threads), "TERM": "xterm-256color", "LINES": "28", "COLUMNS": "110",
                 "PI_TUI_ESC_TIMEOUT": "10", "PI_OFFLINE": "1"},
        )
        output = bytearray()

        def until(needle, timeout=20):
            deadline = time.monotonic() + timeout
            while needle not in output and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
            assert needle in output, (threads, needle, process.poll(), bytes(output[-2500:]))

        try:
            until(b"Global Resources")
            until(b"sample.bend")
            os.write(master, b" ")
            global_settings = agent_dir / "settings.json"
            deadline = time.monotonic() + 10
            while not global_settings.exists() and time.monotonic() < deadline:
                time.sleep(.05)
            assert global_settings.exists(), bytes(output[-2000:])
            actual = json.loads(global_settings.read_text())
            assert actual["extensions"] == ["-extensions/sample.bend"], actual

            os.write(master, b"\t")
            until(b"Project Local Resources")
            os.write(master, b" ")
            project_settings = cwd / ".pi" / "settings.json"
            deadline = time.monotonic() + 10
            while not project_settings.exists() and time.monotonic() < deadline:
                time.sleep(.05)
            assert project_settings.exists(), bytes(output[-2000:])
            resource = str(extension_dir / "sample.bend")
            assert json.loads(project_settings.read_text())["extensions"] == [resource, "-" + resource]
            os.write(master, b"\x1b")
            assert process.wait(timeout=10) == 0, process.stderr.read().decode(errors="replace")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    for count in (1, 4):
        run(count)
    print("config selector one/four threads: ok")
