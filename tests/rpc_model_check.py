#!/usr/bin/env python3
"""RPC model command contract against pinned pi-mono v0.87.1."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-mode.ts").read_bytes()).hexdigest() == "7d4bf1e4291a5320a1ce27504c488622c9a7307ce9e7c2d973f9d95f18a8b2bc"
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/core/agent-session.ts").read_bytes()).hexdigest() == "e5c020bced4ada5c5e116cbd160f66e111016fc717ae30d79994a45527e7f3d7"

def check(label, executable, threads=None):
    env = dict(os.environ, PI_FAUX_API_KEY="faux-key")
    if threads:
        env["BEND_THREADS"] = threads
    cwd = ROOT / "build" / f"rpc-model-{label}-cwd"
    agent_dir = ROOT / "build" / f"rpc-model-{label}-agent"
    cwd.mkdir(parents=True, exist_ok=True)
    agent_dir.mkdir(parents=True, exist_ok=True)
    all_records = [json.loads(line) for line in subprocess.check_output(executable + [str(cwd), str(agent_dir)], cwd=ROOT, env=env).splitlines()]
    records = [record for record in all_records if record.get("type") == "response"]
    assert len(records) == 10, (label, all_records)
    by_id = {record["id"]: record for record in records}
    assert [(r["id"], r["command"], r["success"]) for r in records] == [
        ("available", "get_available_models", True),
        ("missing-provider", "set_model", False),
        ("unknown", "set_model", False),
        ("set", "set_model", True),
        ("state-set", "get_state", True),
        ("cycle", "cycle_model", True),
        ("state-cycle", "get_state", True),
        ("single", "cycle_model", True),
        ("scoped", "cycle_model", True),
        ("state-scoped", "get_state", True),
    ], (label, records)
    models = by_id["available"]["data"]["models"]
    assert [(m["provider"], m["id"]) for m in models] == [("faux", "faux-model"), ("faux", "faux-two")]
    assert models[1]["name"] == "Faux Two" and models[1]["input"] == ["text", "image"]
    assert models[1]["cost"] == {"input": 1, "output": 2, "cacheRead": 3, "cacheWrite": 4}
    assert models[1]["reasoning"] is True and models[1]["contextWindow"] == 64000 and models[1]["maxTokens"] == 2048
    assert by_id["missing-provider"]["error"] == "Invalid command: provider must be a string"
    assert by_id["unknown"]["error"] == "Model not found: faux/missing"
    assert by_id["set"]["data"] == by_id["state-set"]["data"]["model"] == models[1]
    assert by_id["cycle"]["data"] == {"model": models[0], "thinkingLevel": "off", "isScoped": False}
    assert by_id["state-cycle"]["data"]["model"] == models[0]
    assert by_id["single"]["data"] is None
    assert by_id["scoped"]["data"] == {"model": models[1], "thinkingLevel": "low", "isScoped": True}
    assert by_id["state-scoped"]["data"]["model"] == models[1]
    assert by_id["state-scoped"]["data"]["thinkingLevel"] == "low"
    assert by_id["state-set"]["data"]["sessionId"] == by_id["state-cycle"]["data"]["sessionId"]
    print(f"{label}: catalog, validation, scoped/unscoped cycles, and single-model null")

check("Bun", ["bun", "build/rpc-model-session.js"])
check("native1", ["build/rpc-model-session-native"], "1")
check("native4", ["build/rpc-model-session-native"], "4")
