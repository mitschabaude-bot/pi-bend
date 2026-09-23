#!/usr/bin/env python3
"""Pinned Bun RPC fixture: settings, queue order, and explicit unsupported spawn."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = Path(os.environ.get("PI_MONO", "/home/agent/code/pi-mono"))
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-mode.ts").read_bytes()).hexdigest() == "7d4bf1e4291a5320a1ce27504c488622c9a7307ce9e7c2d973f9d95f18a8b2bc"
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/core/agent-session.ts").read_bytes()).hexdigest() == "e5c020bced4ada5c5e116cbd160f66e111016fc717ae30d79994a45527e7f3d7"
def check(label, executable):
    with tempfile.TemporaryDirectory(prefix="rpc-controls-fixture-") as temporary:
        cwd = Path(temporary)
        agent_dir = cwd / "agent"
        agent_dir.mkdir()
        result = subprocess.run(executable + [str(cwd), str(agent_dir)], cwd=ROOT, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr
        records = [json.loads(line) for line in result.stdout.splitlines()]
        responses = [r for r in records if r.get("type") == "response"]
        by_id = {r["id"]: r for r in responses}
        assert by_id["compaction"]["success"] and by_id["retry"]["success"]
        assert by_id["state"]["data"]["autoCompactionEnabled"] is False
        messages = by_id["messages"]["data"]["messages"]
        assert by_id["prompt"]["success"] and any(m.get("role") == "assistant" for m in messages)
        prompt_index = next(i for i, r in enumerate(records) if r.get("id") == "prompt")
        bash_index = next(i for i, r in enumerate(records) if r.get("id") == "run" and r.get("type") == "response")
        starts = [i for i, r in enumerate(records) if r.get("type") == "agent_start"]
        assert prompt_index < bash_index < starts[-1], (label, prompt_index, bash_index, starts)
        if label == "Bun":
            assert not by_id["run"]["success"] and "Function not implemented" in by_id["run"]["error"]
        else:
            assert by_id["run"]["success"] and by_id["run"]["data"]["output"] == "fixture"
            bash_messages = [m for m in messages if m.get("role") == "bashExecution"]
            assert len(bash_messages) == 1 and bash_messages[0].get("excludeFromContext") is True
            entries = by_id["entries"]["data"]["entries"]
            persisted = [e["message"] for e in entries if e.get("type") == "message" and e.get("message", {}).get("role") == "bashExecution"]
            assert len(persisted) == 1 and persisted[0] == bash_messages[0]
        print(f"{label}: settings and bash/prompt queue order")


check("Bun", ["bun", str(ROOT / "build/rpc-controls.js")])
check("native1", [str(ROOT / "build/rpc-controls-native"), "--threads", "1", "--"])
check("native4", [str(ROOT / "build/rpc-controls-native"), "--threads", "4", "--"])
