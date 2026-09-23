#!/usr/bin/env python3
"""Mounted tree/fork selection against pi f07218c4d interactive selectors."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
SOURCES = {
    "interactive-mode.ts": ("packages/coding-agent/src/modes/interactive/interactive-mode.ts", "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"),
    "tree-selector.ts": ("packages/coding-agent/src/modes/interactive/components/tree-selector.ts", "767bee39141acf21f70b4e8c01c62dfefa588bc2edd8fe2093886a70a77e115f"),
    "user-message-selector.ts": ("packages/coding-agent/src/modes/interactive/components/user-message-selector.ts", "bd48d99cc3eea80d833f9933d4281d2b79b40d7c63727663b2a4c9605930369a"),
}
for label, (source, digest) in SOURCES.items():
    assert hashlib.sha256((UPSTREAM / source).read_bytes()).hexdigest() == digest, label
BINARY = Path(os.environ.get("PI_BEND_TREE_RUN", ROOT / "build/tree-run-native")).resolve()


def scenario(threads, mode):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-tree-run-") as cwd:
        agent_dir = Path(cwd) / "agent"
        agent_dir.mkdir()
        if mode == "fork":
            (agent_dir / "settings.json").write_text(json.dumps({"doubleEscapeAction": "fork"}))
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), cwd, str(agent_dir), "dark"],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        output = bytearray()

        def read_for(seconds):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if select.select([master], [], [], .08)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break

        def until(needle, timeout=8):
            deadline = time.monotonic() + timeout
            while needle not in output and time.monotonic() < deadline:
                read_for(.08)
            assert needle in output, (threads, mode, needle, process.poll(), bytes(output[-1000:]))

        try:
            until(b"theme-fixture")
            os.write(master, b"first\r")
            until(b"late-response")
            read_for(.25)  # Wait for agent_settled before opening a selector.
            start = len(output)
            os.write(master, b"\x1b")
            time.sleep(.2)
            os.write(master, b"\x1b")
            title = b"Session Tree" if mode == "tree" else b"Fork from Message"
            until(title)
            assert title in output[start:], (threads, mode)
            assert b"user: first" in output[start:], (threads, mode)
            if mode == "tree":
                assert b"assistant: late-response" in output[start:], (threads, mode)
                controls_at = len(output)
                os.write(master, b"late")
                deadline = time.monotonic() + 5
                while b"(1/1)" not in output[controls_at:]:
                    read_for(.08)
                    assert time.monotonic() < deadline, (threads, "search", bytes(output[-1200:]))
                assert b"Type to search:" in output[controls_at:]
                os.write(master, b"\x1b")
                read_for(.4)
                controls_at = len(output)
                os.write(master, b"\x0f")
                read_for(.4)
                assert b"[no-tools]" in output[controls_at:], (threads, "filter", bytes(output[-1200:]))
                os.write(master, b"\x1b[A")
                read_for(.2)
                controls_at = len(output)
                os.write(master, b"\x1b[1;5D")
                read_for(.4)
                assert b"(1/1)" in output[controls_at:], (threads, "fold", bytes(output[-1200:]))
                controls_at = len(output)
                os.write(master, b"\x1b[1;5C")
                read_for(.4)
                assert b"(1/2)" in output[controls_at:], (threads, "unfold", bytes(output[-1200:]))
            selected_at = len(output)
            os.write(master, b"\r")
            deadline = time.monotonic() + 5
            while b"first" not in output[selected_at:] and time.monotonic() < deadline:
                read_for(.08)
            read_for(.25)
            selected = bytes(output[selected_at:])
            draft = selected.rfind(b"first\x1b[7m")
            assert draft >= 0, (threads, mode, selected[-1200:])
            assert b"late-response" not in selected[draft:], (threads, mode, selected[-1200:])
            os.write(master, b"\x03\x03")
            stderr = process.communicate(timeout=12)[1]
            assert process.returncode == 0, (threads, mode, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, (threads, mode)
            assert not stderr, (threads, mode, stderr.decode(errors="replace"))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: {mode} selected user entry, replaced session view, restored terminal")


for threads in (1, 4):
    for mode in ("tree", "fork"):
        scenario(threads, mode)
