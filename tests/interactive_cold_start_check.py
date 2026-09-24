#!/usr/bin/env python3
"""A credential-free native terminal must allow /login before a model exists."""
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
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli-cold-start"))

for threads in (1, 4):
    with tempfile.TemporaryDirectory(prefix="pi-bend-cold-start-") as place:
        project = Path(place)
        agent_dir = project / "agent"
        env = {**os.environ, "TERM": "xterm-256color", "PI_CODING_AGENT_DIR": str(agent_dir)}
        for name in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_OAUTH_TOKEN", "GEMINI_API_KEY", "CEREBRAS_API_KEY"):
            env[name] = ""
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen([str(BINARY), "--threads", str(threads), "--", "--no-tools"], cwd=project, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env)
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
            assert needle in output[start:], (threads, needle, process.poll(), bytes(output[start:][-1000:]))

        try:
            until(b"no-model")
            start = len(output)
            os.write(master, b"/model\r")
            until(b"No models available. Use /login", start)
            start = len(output)
            os.write(master, b"What is two plus two?\r")
            until(b"No model selected", start)
            start = len(output)
            os.write(master, b"/login\r")
            until(b"Choose a provider", start)
            os.write(master, b"\x1b")
            until(b"Login cancelled", start)
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
    print(f"native{threads}: model-free terminal, login chooser, rejection, restoration")
