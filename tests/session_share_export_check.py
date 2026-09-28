#!/usr/bin/env python3
"""Share metadata extends the exported path without rewriting conversation links."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_SHARE_EXPORT", ROOT / "build/session-share-export"))

for threads in (1, 4):
    run = subprocess.run([str(BINARY), "--threads", str(threads)], cwd=ROOT, capture_output=True, timeout=20, check=True)
    normal_text, share_text = run.stdout.decode().split("--SHARE--\n")
    normal = [json.loads(line) for line in normal_text.splitlines() if line]
    shared = [json.loads(line) for line in share_text.splitlines() if line]
    assert shared[:-1] == normal
    assert [entry["id"] for entry in normal[1:]] == ["a", "c"]
    assert [entry["parentId"] for entry in normal[1:]] == [None, "a"]
    metadata = shared[-1]
    assert {key: metadata[key] for key in ("type", "customType", "id", "parentId", "timestamp")} == {
        "type": "custom", "customType": "pi.share", "id": "abcdef12",
        "parentId": "c", "timestamp": "2026-02-01T00:00:00.000Z",
    }
    assert metadata["data"] == {
        "systemPrompt": "You are helpful.",
        "tools": [{"name": "read", "description": "Read a file", "parameters": "schema"}],
    }
    print(f"native{threads}: share extends the selected path with presentation metadata")
