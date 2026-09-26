#!/usr/bin/env python3
"""Native ws:// exchanges; RFC frames are generated/decoded independently here.

Build tests/websocket-client.bend to build/websocket-client(.js), then run.
Bun's WebSocket is the external oracle for valid message/control exchanges.
"""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import threading
import tempfile
from fetch_https_check import trusted_context

ROOT = Path(__file__).resolve().parents[1]
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def frame(opcode, payload, final=True):
    n = len(payload)
    length = bytes([n]) if n < 126 else b"\x7e" + struct.pack("!H", n) if n < 65536 else b"\x7f" + struct.pack("!Q", n)
    return bytes([(0x80 if final else 0) | opcode]) + length + payload


def exact(conn, size):
    value = b""
    while len(value) < size:
        more = conn.recv(size - len(value))
        if not more:
            raise EOFError
        value += more
    return value


def receive(conn):
    first, second = exact(conn, 2)
    assert first & 0x80 and not first & 0x70, (first, second)
    assert second & 0x80, "client frames must be masked"
    size = second & 0x7f
    if size == 126:
        size, = struct.unpack("!H", exact(conn, 2))
    elif size == 127:
        size, = struct.unpack("!Q", exact(conn, 8))
    mask = exact(conn, 4)
    payload = exact(conn, size)
    return first & 15, bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(5)
        try:
            header = b""
            while not header.endswith(b"\r\n\r\n"):
                header += exact(conn, 1)
                assert len(header) <= 65536
            lines = header.decode("ascii").split("\r\n")
            assert lines[0] == "GET /responses?fixture=1 HTTP/1.1", lines[0]
            fields = dict(line.lower().split(": ", 1) for line in lines[1:] if line)
            assert fields["authorization"] == "bearer fixture"
            assert fields["sec-websocket-version"] == "13"
            # Preserve the case-sensitive nonce from the original headers.
            key = next(line.split(": ", 1)[1] for line in lines if line.lower().startswith("sec-websocket-key:"))
            assert len(base64.b64decode(key, validate=True)) == 16
            self.server.handshakes += 1
            accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
            if self.server.mode == "bad-accept":
                accept = "wrong"
            response = f"HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n".encode()
            conn.sendall(response + (frame(9, b"initial") if self.server.mode == "fragmented" else b""))
            if self.server.mode == "bad-accept":
                assert not conn.recv(1), "client accepted invalid handshake"
                return
            while True:
                opcode, payload = receive(conn)
                if opcode == 8:
                    conn.sendall(frame(8, payload))
                    return
                if opcode == 10:
                    self.server.pongs.append(payload)
                    continue
                assert opcode == 1, opcode
                self.server.requests.append(payload.decode("utf-8"))
                if self.server.mode == "cancel":
                    assert not conn.recv(1), "cancelled reader left connection open"
                    return
                if self.server.mode == "close":
                    conn.sendall(frame(8, struct.pack("!H", 1000) + "finished ☃".encode()))
                    return
                if self.server.mode == "binary":
                    conn.sendall(frame(2, bytes(range(256))))
                elif self.server.mode == "fragmented":
                    message = "snow ☃ and emoji 😀".encode()
                    cut = 6  # splits the snowman's UTF-8 sequence
                    wire = frame(1, message[:cut], False) + frame(9, b"middle") + frame(0, message[cut:])
                    for i in range(0, len(wire), 3):
                        conn.sendall(wire[i:i+3])
                else:
                    conn.sendall(frame(1, payload))
        except EOFError:
            pass
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as error:
            self.server.errors.append(repr(error))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = False


def run(argv, mode, payload, env=None, tls=None):
    with Server(("127.0.0.1", 0), Handler) as server:
        if tls:
            server.socket = tls[0].wrap_socket(server.socket, server_side=True)
        server.mode = mode
        server.requests, server.pongs, server.errors = [], [], []
        server.handshakes = 0
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"{'wss://localhost' if tls else 'ws://127.0.0.1'}:{server.server_address[1]}/responses?fixture=1"
            result = subprocess.run([*argv, url, mode, payload, base64.b64encode(tls[1]).decode() if tls else ""], cwd=ROOT, env=env, capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, (mode, result.stderr, result.stdout[:200])
            assert not result.stderr, result.stderr
            server.shutdown()
            thread.join()
            server.server_close()
            assert not server.errors, (mode, server.errors)
            assert server.handshakes == 1, (mode, result.stdout, server.errors)
            assert server.requests == ([] if mode == "bad-accept" else [payload] * (2 if mode == "reuse" else 1)), (mode, server.requests)
            assert server.pongs == ([b"initial", b"middle"] if mode == "fragmented" else []), (mode, server.pongs)
            return result.stdout.splitlines()
        finally:
            server.shutdown()
            thread.join()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("bun", "native", "all"), default="all")
    args = parser.parse_args()
    lanes = []
    if args.backend in ("bun", "all"):
        lanes.append(("bun", ["bun", "build/websocket-client.js"], os.environ.copy()))
    if args.backend in ("native", "all"):
        lanes.extend((f"native{n}", [str(ROOT / "build/websocket-client")], {**os.environ, "BEND_THREADS": str(n)}) for n in (1, 4))
    for mode, payload in [("echo", 'response.create ☃'), ("reuse", "second turn"), ("fragmented", "fragmented"), ("binary", "binary"), ("medium", "a" * 200), ("large", "b" * 70000), ("close", "close")]:
        expected = run(["bun", "tests/websocket_client_reference.ts"], mode, payload)
        for name, argv, env in lanes:
            actual = run(argv, mode, payload, env)
            assert actual == expected, (name, mode, str(actual)[:200], str(expected)[:200])
            print(f"{name}: {mode} messages/masking/headers/connection MATCH")
    for mode, expected in [("bad-accept", ["error|Invalid WebSocket upgrade response"]), ("cancel", ["error|WebSocket read failed"])]:
        for name, argv, env in lanes:
            assert run(argv, mode, mode, env) == expected, (name, mode)
            print(f"{name}: {mode} rejection/cleanup PASS")
    with tempfile.TemporaryDirectory(prefix="pi-websocket-tls-") as tmp:
        tls = trusted_context(Path(tmp), "localhost")
        for mode, payload in [("echo", "encrypted ☃"), ("reuse", "encrypted continuation"), ("fragmented", "encrypted fragments")]:
            expected = run(["bun", "tests/websocket_client_reference.ts"], mode, payload, tls=tls)
            for name, argv, env in lanes:
                assert run(argv, mode, payload, env, tls) == expected, (name, mode, "wss")
                print(f"{name}: wss {mode} authorized TLS/messages/cleanup MATCH")


if __name__ == "__main__":
    main()
