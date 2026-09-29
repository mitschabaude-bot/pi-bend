#!/usr/bin/env python3
"""The public JSONL export chooses a dated path and preserves explicit paths."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_EXPORT_PATH", ROOT / "build/session-export-path"))

for threads in (1, 4):
    with tempfile.TemporaryDirectory(prefix="pi-bend-export-") as place:
        cwd = Path(place)
        run = subprocess.run([str(BINARY), "--threads", str(threads)], cwd=cwd, capture_output=True, text=True, timeout=20, check=True)
        paths = [Path(line) for line in run.stdout.splitlines()]
        assert paths == [cwd / "session-2026-02-01T12-34-56-789Z.jsonl", cwd / "nested/explicit.jsonl"], paths
        for path in paths:
            header = json.loads(path.read_text().splitlines()[0])
            assert (header["id"], header["timestamp"]) == ("export-id", "2026-02-01T12:34:56.789Z")
    print(f"native{threads}: default and explicit JSONL export paths write the session")
