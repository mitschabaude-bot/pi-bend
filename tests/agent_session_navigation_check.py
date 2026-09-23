#!/usr/bin/env python3
"""No-summary navigateTree projection pinned to pi v0.87.1."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/core/agent-session.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "e5c020bced4ada5c5e116cbd160f66e111016fc717ae30d79994a45527e7f3d7"


def check(binary, threads):
    with tempfile.TemporaryDirectory(prefix="pi-navigation-") as cwd:
        agent = Path(cwd) / "agent"
        agent.mkdir()
        command = (["bun", str(binary)] if str(binary).endswith(".js") else [str(binary), "--threads", str(threads), "--"])
        completed = subprocess.run(command + ["navigate", cwd, str(agent)], cwd=ROOT, capture_output=True, text=True, timeout=60)
        assert completed.returncode == 0, completed.stderr[-2000:]
        events = [json.loads(line) for line in completed.stdout.splitlines()]
        navigation = [event for event in events if event["type"] == "navigation"]
        assert len(navigation) == 2 and navigation[1]["editorText"] is None
        nav = navigation[0]
        trees = [event for event in events if event["type"] == "session_tree"]
        assert len(trees) == 1, trees  # Selecting the current leaf is a no-op.
        tree = trees[0]
        assert nav["editorText"] == "two" and nav["leafId"] == tree["newLeafId"]
        assert tree["oldLeafId"] != tree["newLeafId"]
        assert navigation[1]["leafId"] == tree["newLeafId"]
        assert next(event for event in events if event["type"] == "navigation_error")["error"] == "Entry missing-entry not found"
        messages = [event["messages"] for event in events if event["type"] == "messages"]
        def text(message):
            return "".join(block.get("text", "") for block in message["content"])
        assert [[text(message) for message in group] for group in messages] == [
            ["one", "a1"], ["one", "a1", "replacement", "branched"]
        ]
        entries = next(event for event in events if event["type"] == "entries")
        assert len(entries["kinds"]) == 6, entries  # Old branch remains in append-only history.
        assert [event["type"] for event in events].count("prompt_done") == 3
    print(f"{binary.name} threads={threads}: selected user restores draft; context branches; history retained")


check(ROOT / "build/session-navigation.js", 0)
native = ROOT / "build/session-navigation-fixture"
if native.exists():
    for threads in (1, 4):
        check(native, threads)
