"""Custom message frames against pinned pi, plus native lifecycle assertions."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
env = dict(os.environ, FORCE_COLOR="1", TERM="xterm-256color")
env.pop("NO_COLOR", None)
expected = subprocess.check_output(["bun", "tests/custom_message_reference.ts"], cwd=ROOT, env=env)
for backend, command in [
    ("Bun", ["bun", "build/custom-message.js"]),
    ("native-1", ["build/custom-message", "--threads", "1"]),
    ("native-4", ["build/custom-message", "--threads", "4"]),
]:
    output = subprocess.check_output(command, cwd=ROOT, env=env)
    frames = b"".join(row + b"\n" for row in output.split(b"\n") if b"\x1e" in row)
    assert frames == expected, (backend, frames.decode(), expected.decode())
    print(f"{backend}: custom/default/failure frames and reentrant capture/focus traces match pi; lifecycle checks pass")
