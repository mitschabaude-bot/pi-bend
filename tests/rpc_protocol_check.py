#!/usr/bin/env python3
"""Byte-compare native JSONL framing with pi v0.87.1's actual jsonl.ts."""
import hashlib
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = Path(os.environ.get("PI_MONO", "/home/agent/code/pi-mono"))
JSONL = UPSTREAM / "packages/coding-agent/src/modes/rpc/jsonl.ts"
RPC_MODE = UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-mode.ts"
assert hashlib.sha256(JSONL.read_bytes()).hexdigest() == "95723d349fcebad1f1da7ce103d02ba7d5e2c876b7d178d41d8b56beedbd93e0"
assert hashlib.sha256(RPC_MODE.read_bytes()).hexdigest() == "7d4bf1e4291a5320a1ce27504c488622c9a7307ce9e7c2d973f9d95f18a8b2bc"

def run(command, env=None):
    return subprocess.check_output(command, cwd=ROOT, env=env)

expected = run(["bun", "tests/rpc_protocol_reference.ts"])
for label, command, threads in [
    ("Bun", ["bun", "build/rpc-protocol.js"], None),
    ("native1", ["build/rpc-protocol-native"], "1"),
    ("native4", ["build/rpc-protocol-native"], "4"),
]:
    env = dict(os.environ)
    if threads: env["BEND_THREADS"] = threads
    actual = run(command, env)
    if actual != expected:
        raise AssertionError(f"{label} RPC JSONL differs from pinned upstream:\n{actual!r}\n!=\n{expected!r}")
    print(f"{label}: 6 byte-exact pinned RPC framing/response cases")
