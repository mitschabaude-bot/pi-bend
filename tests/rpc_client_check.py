#!/usr/bin/env python3
"""upstream rpc-client-clear-queue, rpc-client-clone and
rpc-client-process-exit suites on packages/coding-agent/test/rpc-client.bend.

Build: bun build/bend-process-files/bend2/main.ts packages/coding-agent/test/rpc-client.bend -o build/rpc-client.js
       sh scripts/build-pure.sh packages/coding-agent/test/rpc-client.bend build/rpc-client-native
"""
from upstream_pin import UPSTREAM
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for source, digest in [
    ("packages/coding-agent/test/rpc-client-clear-queue.test.ts", "1c2d691ea48ffccc3d06a426721f6d869608de3ad9c208397ff5b6d33a369746"),
    ("packages/coding-agent/test/rpc-client-clone.test.ts", "4402c2a7b168016cd0d2fbb578843d27181a8b55353d56f607d293060aee8d6c"),
    ("packages/coding-agent/test/rpc-client-process-exit.test.ts", "7469f8683c0f227985e908cce021922e64ee85dcede7e49df6a1fe0e8cbc6cc8"),
    ("packages/coding-agent/src/modes/rpc/rpc-client.ts", "6d1a586cfa38fd3be62d21feacfe9e700f6e88d4fc842adcc345130acd0d57ff"),
]:
    assert hashlib.sha256((UPSTREAM / source).read_bytes()).hexdigest() == digest, source

FAKE = ["PASS RpcClient clearQueue > sends the clear_queue RPC command", "PASS RpcClient clone > sends the clone RPC command"]
EXIT = ["PASS RpcClient child process failures > rejects an in-flight request when the child process exits"]


def run(label, command, expected, threads=None):
    env = dict(os.environ)
    if threads:
        env["BEND_THREADS"] = threads
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0 and result.stdout.splitlines() == expected, (label, result.stdout, result.stderr)
    print(f"{label}: {len(expected)} pass")


run("Bun fake transport", ["bun", "build/rpc-client.js", "fake"], FAKE)
for threads in ("1", "4"):
    run(f"native{threads} fake transport", ["build/rpc-client-native", "fake"], FAKE, threads)
    with tempfile.TemporaryDirectory(prefix="pi-rpc-client-exit-") as temporary:
        run(f"native{threads} child process", ["build/rpc-client-native", "process", str(Path(temporary, "child"))], EXIT, threads)
