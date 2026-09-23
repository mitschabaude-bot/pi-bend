#!/usr/bin/env python3
"""Check the RPC command/worker lifecycle against the pinned prompt contract."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "7d4bf1e4291a5320a1ce27504c488622c9a7307ce9e7c2d973f9d95f18a8b2bc"

def check(label, executable, threads=None):
    env = dict(os.environ)
    if threads: env["BEND_THREADS"] = threads
    output = subprocess.check_output(executable + ["build/rpc-test-cwd", "build/rpc-test-agent"], cwd=ROOT, env=env)
    records = [json.loads(line) for line in output.splitlines()]
    responses = [r for r in records if r.get("type") == "response"]
    expected = [
        ("levels", "get_available_thinking_levels", True),
        ("cycle", "cycle_thinking_level", True),
        ("steering-mode", "set_steering_mode", True),
        ("follow-mode", "set_follow_up_mode", True),
        ("steered", "steer", True),
        ("followed", "follow_up", True),
        ("queue", "clear_queue", True),
        ("e", "get_entries", True),
        ("missing", "get_entries", False),
        ("name", "set_session_name", True),
        ("name2", "set_session_name", True),
        ("tree", "get_tree", True),
        ("forks", "get_fork_messages", True),
        ("p", "prompt", True),
        ("u", "unknown", False),
        ("bad", "prompt", False),
        ("image-bad", "steer", False),
        ("tail", "unknown", False),
    ]
    assert [(r.get("id"), r["command"], r["success"]) for r in responses] == expected, (label, responses)
    assert responses[0]["data"] == {"levels": ["off"]}
    assert responses[1]["data"] is None
    assert responses[6]["data"] == {"steering": ["queued steer"], "followUp": ["queued follow"]}
    assert responses[7]["data"] == {"entries": [], "leafId": None}
    assert responses[8]["error"] == "Entry not found: nowhere"
    tree = responses[11]["data"]["tree"]
    assert tree[0]["entry"]["type"] == "session_info"
    assert tree[0]["entry"]["name"] == "rpc tree"
    assert tree[0]["children"][0]["entry"]["name"] == "rpc nested"
    assert tree[0]["children"][0]["children"] == []
    assert responses[12]["data"] == {"messages": []}
    assert responses[15]["error"] == "Invalid command: message must be a string"
    assert responses[16]["error"] == "Invalid command: data must be a string"
    prompt_index = next(i for i, r in enumerate(records) if r.get("id") == "p")
    start_index = next(i for i, r in enumerate(records) if r.get("type") == "agent_start")
    settled_index = next(i for i, r in enumerate(records) if r.get("type") == "agent_settled")
    assert prompt_index < start_index < settled_index == len(records) - 1, (label, records)
    assert any(r.get("type") == "message_end" and r.get("message", {}).get("role") == "assistant" and r["message"]["content"][0]["text"] == "answer" for r in records)
    assert any(r.get("type") == "message_start" and r.get("message", {}).get("role") == "user" and r["message"]["content"][1] == {"type": "image", "data": "AA==", "mimeType": "image/png"} for r in records)
    assert sum(r.get("type") == "agent_start" for r in records) == 1
    print(f"{label}: prompt ACK precedes events; EOF drains through agent_settled; strict command errors")

(ROOT / "build/rpc-test-cwd").mkdir(parents=True, exist_ok=True)
(ROOT / "build/rpc-test-agent").mkdir(parents=True, exist_ok=True)
check("Bun", ["bun", "build/rpc-session.js"])
check("native1", ["build/rpc-session-native"], "1")
check("native4", ["build/rpc-session-native"], "4")
