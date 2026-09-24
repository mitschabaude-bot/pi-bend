#!/usr/bin/env python3
"""A browser callback and a manual result race through the native loopback listener."""

import os
from pathlib import Path
import socket
import subprocess
import time

root = Path(__file__).resolve().parents[1]
binary = Path(os.environ.get("PI_BEND_CALLBACK", root / "build/anthropic-oauth-callback"))


def request(path):
    deadline = time.monotonic() + 5
    while True:
        try:
            with socket.create_connection(("127.0.0.1", 53692), timeout=1) as connection:
                connection.sendall(f"GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode())
                chunks = []
                while chunk := connection.recv(4096):
                    chunks.append(chunk)
                return b"".join(chunks)
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.02)


for threads in (1, 4):
    process = subprocess.Popen([str(binary), "--threads", str(threads), "--", "browser"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        bad = request("/callback?code=wrong&state=bad")
        assert bad.startswith(b"HTTP/1.1 400 Bad Request")
        assert process.poll() is None
        good = request("/callback?code=authorized&state=state_test")
        assert good.startswith(b"HTTP/1.1 200 OK")
        out, err = process.communicate(timeout=5)
        assert process.returncode == 0 and out == b"authorized\n" and not err, (out, err)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    manual = subprocess.run([str(binary), "--threads", str(threads), "--", "manual"], cwd=root, capture_output=True, timeout=5, check=True)
    assert manual.stdout == b"manual\n" and not manual.stderr
    print(f"native{threads}: rejected state, browser callback, manual cancellation")
