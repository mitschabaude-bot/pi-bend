#!/usr/bin/env python3
"""Mounted Radius API-key login selects a model from a freshly fetched catalog."""
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
import threading
import time

from radius_check import FRESH, Gateway


ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli")).resolve()


def scenario(threads, stalled=False):
    gate = threading.Event() if stalled else None
    gateway = Gateway(FRESH, config_wait=gate)
    try:
        with tempfile.TemporaryDirectory(prefix="pi-radius-login-") as place:
            home = Path(place)
            agent = home / ".pi" / "agent"
            agent.mkdir(parents=True)
            (agent / "models.json").write_text(json.dumps({"providers": {"radius": {
                "baseUrl": gateway.url + "/v1", "oauth": "radius", "name": "Radius"
            }}}))
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
            env = {"HOME": place, "PATH": os.environ["PATH"], "LANG": "C.UTF-8",
                   "TERM": "xterm-256color", "PI_CODING_AGENT_DIR": str(agent),
                   "PI_BEND_PACKAGE_DIR": str(ROOT), "BEND_THREADS": str(threads)}
            process = subprocess.Popen([str(BINARY)], cwd=place, env=env,
                                       stdin=slave, stdout=slave, stderr=subprocess.PIPE)
            os.close(slave)
            output = bytearray()

            def until(needle, start=0, timeout=15):
                deadline = time.monotonic() + timeout
                while needle not in output[start:] and time.monotonic() < deadline:
                    if select.select([master], [], [], .2)[0]:
                        try:
                            output.extend(os.read(master, 65536))
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                            break
                assert needle in output[start:], (threads, needle, process.poll(), bytes(output[-800:]))

            try:
                until(b"no-model")
                # The footer can render before startup installs the submit handler.
                start = len(output)
                os.write(master, b"/login radius\r")
                for _ in range(20):
                    try:
                        until(b"Select authentication method for Radius:", start, 1)
                        break
                    except AssertionError:
                        assert process.poll() is None
                        os.write(master, b"\r")
                else:
                    raise AssertionError("/login did not open")
                start = len(output)
                os.write(master, b"\x1b[B\r")
                until(b"Enter Radius API key", start)
                start = len(output)
                os.write(master, b"radius-test-key\r")
                until(b"Saved API key for radius", start)
                if stalled:
                    deadline = time.monotonic() + 10
                    while not gateway.requests and time.monotonic() < deadline:
                        time.sleep(.05)
                    assert gateway.requests, "catalog request never started"
                else:
                    until(b"Selected balanced", start)
                assert any(request["path"] == "/v1/config" and
                           request["headers"].get("authorization") == "Bearer radius-test-key"
                           for request in gateway.requests), gateway.requests
                auth = json.loads((agent / "auth.json").read_text())
                assert auth["radius"]["key"] == "radius-test-key"
                os.write(master, b"/quit\r")
                assert process.wait(timeout=5) == 0
                print(f"Radius login: native {threads} thread(s) " +
                      ("quit during stalled refresh" if stalled else "selected balanced and exited"))
            finally:
                if gate is not None:
                    gate.set()
                if process.poll() is None:
                    process.kill()
                    process.wait()
                os.close(master)
    finally:
        gateway.close()


if __name__ == "__main__":
    for count in (1, 4):
        scenario(count)
        scenario(count, stalled=True)
