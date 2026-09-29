#!/usr/bin/env python3
"""Compare upstream and native CLI output channels for one-shot metadata commands."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from upstream_pin import UPSTREAM  # noqa: F401

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
CASES = [
    ("plain-help", ["--help"], "Usage:", "stdout"),
    ("json-help", ["--mode", "json", "--help", "--approve"], "Usage:", "stderr"),
    ("rpc-help", ["--mode", "rpc", "--help"], "Usage:", "stderr"),
    ("text-help", ["--mode", "text", "--help"], "Usage:", "stderr"),
    ("print-help", ["--print", "--help"], "Usage:", "stderr"),
    ("plain-models", ["--list-models"], "model", "stdout"),
    ("json-models", ["--mode", "json", "--list-models"], "model", "stderr"),
    ("rpc-models", ["--mode", "rpc", "--list-models"], "model", "stderr"),
    ("print-models", ["--print", "--list-models"], "model", "stderr"),
]


def run(binary, args, threads):
    with tempfile.TemporaryDirectory(prefix="pi-stdout-clean-") as root:
        home, project = Path(root) / "home", Path(root) / "project"
        home.mkdir()
        project.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.endswith("_API_KEY")}
        env.update(HOME=str(home), PI_CODING_AGENT_DIR=str(home / ".pi" / "agent"),
                   PI_OFFLINE="1", PI_SKIP_VERSION_CHECK="1", BEND_THREADS=str(threads),
                   PI_BEND_PACKAGE_DIR=str(ROOT))
        return subprocess.run([str(binary), *args], cwd=project, env=env,
                              capture_output=True, text=True, timeout=30)


def check(label, result, marker, channel):
    assert result.returncode == 0, (label, result.returncode, result.stderr[:300])
    selected = result.stdout if channel == "stdout" else result.stderr
    other = result.stderr if channel == "stdout" else result.stdout
    assert marker in selected, (label, repr(selected[:300]))
    assert marker not in other, (label, repr(other[:300]))
    if channel == "stderr":
        assert result.stdout == "", (label, repr(result.stdout[:300]))


def main():
    reference = shutil.which("pi")
    assert reference, "upstream pi must be installed"
    for name, args, marker, channel in CASES:
        check("pi " + name, run(reference, args, 1), marker, channel)
        for threads in (1, 4):
            check(f"bend{threads} {name}", run(BINARY, args, threads), marker, channel)
        print(f"{name}: upstream/native1/native4 route output to {channel}")


if __name__ == "__main__":
    main()
