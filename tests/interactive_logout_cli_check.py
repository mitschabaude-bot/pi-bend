#!/usr/bin/env python3
"""A mounted CLI removes stored OAuth and refreshes its model catalog."""
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
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli-logout-current"))

for threads in (1, 4):
    with tempfile.TemporaryDirectory(prefix="pi-bend-logout-") as place:
        project = Path(place)
        agent_dir = project / "agent"
        agent_dir.mkdir()
        auth_file = agent_dir / "auth.json"
        auth_file.write_text(json.dumps({"openai-codex": {"type": "oauth", "refresh": "fixture", "access": "fixture", "expires": 4102444800000}}))
        auth_file.chmod(0o600)
        env = {**os.environ, "TERM": "xterm-256color", "PI_CODING_AGENT_DIR": str(agent_dir)}
        for key in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_OAUTH_TOKEN", "GEMINI_API_KEY", "CEREBRAS_API_KEY"):
            env[key] = ""
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(["env", f"BEND_THREADS={threads}", str(BINARY), "--no-tools"], cwd=project, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env)
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

        try:
            until(b"gpt-5.5")
            start = len(output)
            os.write(master, b"/model\r")
            until(b"openai-codex/gpt", start)
            os.write(master, b"\x1b")
            time.sleep(.2)
            start = len(output)
            os.write(master, b"/logout\r")
            until(b"Stored credentials", start)
            os.write(master, b"\r")
            until(b"Logged out of OpenAI Codex", start)
            assert json.loads(auth_file.read_text()) == {}
            start = len(output)
            os.write(master, b"/model\r")
            until(b"No models available. Use /login", start)
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
    print(f"native{threads}: stored OAuth removed; model catalog refreshed; terminal restored")
