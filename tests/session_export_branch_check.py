#!/usr/bin/env python3
"""Current-branch JSONL has a fresh header and linear parent links."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_EXPORT_BRANCH", ROOT / "build/session-export-branch"))

for threads in (1, 4):
    result = subprocess.run([str(BINARY), "--threads", str(threads)], cwd=ROOT, capture_output=True, timeout=20)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    records = [json.loads(line) for line in result.stdout.splitlines() if line]
    assert records[0] == {"type": "session", "version": 3, "id": "export-session", "timestamp": "2026-02-01T00:00:00.000Z", "cwd": "/tmp/export"}
    assert [entry["id"] for entry in records[1:]] == ["a", "c"]
    assert [entry["parentId"] for entry in records[1:]] == [None, "a"]
    print(f"native{threads}: selected branch only, fresh header, contiguous parent links")
