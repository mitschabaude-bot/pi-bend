#!/usr/bin/env python3
"""Compare shortcut-warning colors and source labels with pi's own formatter.

Build with: BEND_TUS=8 sh scripts/build-pure.sh tests/header-shortcut-issues.bend build/header-shortcut-issues
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
reference = subprocess.check_output(["bun", "tests/header-shortcut-issues-reference.ts"], cwd=ROOT, env={**os.environ, "HOME": "/home/agent"})
for threads in ("1", "4"):
    output = subprocess.check_output(["build/header-shortcut-issues"], cwd=ROOT, env={**os.environ, "BEND_THREADS": threads})
    assert output == reference, (threads, output, reference)
    print(f"native {threads}: exact warning colors/source labels; quiet header refresh and clearing")
