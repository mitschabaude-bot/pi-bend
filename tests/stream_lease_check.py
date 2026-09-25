#!/usr/bin/env python3
"""Run the end-to-end stream lease fixture natively on one and four threads.

The provider lends an owned event stream and records its release; the trace
must show exactly one release right after the leased response's final message,
a cleanup failure reported through the loop's typed error path, no release for
a failed open, and an earlier listener failure surviving a release failure.
"""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'packages/agent/test/stream-lease.bend', 'build/stream-lease-check'], cwd=root, check=True)
for threads in ['1', '4']:
    subprocess.run(['build/stream-lease-check', '--threads', threads], cwd=root, check=True, timeout=120)
