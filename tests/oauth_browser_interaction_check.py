#!/usr/bin/env python3
"""Native browser/manual arbitration, typed failures and resource cleanup."""
import os
from pathlib import Path
import socket
import subprocess

root = Path(__file__).resolve().parents[1]
binary = Path(os.environ.get("PI_BEND_BROWSER_INTERACTION", root / "build/oauth-browser-interaction"))


def assert_closed():
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 53693))
        listener.listen()


def request(path):
    with socket.create_connection(("127.0.0.1", 53693), timeout=2) as connection:
        connection.sendall(f"GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode())
        data = b""
        while chunk := connection.recv(4096):
            data += chunk
        return data


for threads in (1, 4):
    command = [str(binary), "--threads", str(threads), "--"]
    process = subprocess.Popen(command + ["browser"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert process.stdout.readline().startswith(b"ready ")
        for target in ("/wrong?code=bad&state=test_state", "/auth/callback?code=bad", "/auth/callback?code=bad&state=wrong"):
            assert request(target).startswith(b"HTTP/1.1 400")
            assert process.poll() is None
        assert request("/auth/callback?code=browser_code&state=test_state").startswith(b"HTTP/1.1 200")
        out, err = process.communicate(timeout=5)
        assert process.returncode == 0 and out == b"code browser_code\n" and not err, (out, err)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    assert_closed()
    for mode, expected in (("manual", "code manual_code"), ("error", "error prompt failed"), ("wrong-state", "error OAuth state mismatch or missing authorization code"), ("cancel", "error Login cancelled")):
        result = subprocess.run(command + [mode], cwd=root, capture_output=True, text=True, timeout=5, check=True)
        assert result.stdout.splitlines()[-1] == expected and not result.stderr, result
        assert_closed()
    with socket.socket() as occupied:
        occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        occupied.bind(("127.0.0.1", 53693))
        occupied.listen()
        result = subprocess.run(command + ["manual"], cwd=root, capture_output=True, text=True, timeout=5, check=True)
        assert result.stdout.splitlines()[-1] == "code manual_code" and not result.stderr
    print(f"native{threads}: callback/manual winners, state validation, typed failure, cancellation and unavailable-port fallback")
