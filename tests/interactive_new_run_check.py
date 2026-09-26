#!/usr/bin/env python3
"""Mounted /new and /clear replace the live session and keep the editor usable."""
from upstream_pin import UPSTREAM
import base64
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
SOURCE = UPSTREAM / "packages/coding-agent/src/modes/interactive/interactive-mode.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0af3d03d1af8bbe7672c704aa9414d14bd7f15b511320acc038af7148d214388"
BINARY = Path(os.environ.get("PI_BEND_NEW_RUN", ROOT / "build/interactive-new-run")).resolve()


def scenario(threads, shortcuts=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
    original = termios.tcgetattr(slave)
    with tempfile.TemporaryDirectory(prefix="pi-interactive-new-") as place:
        cwd = Path(place)
        agent_dir = cwd / "agent"
        agent_dir.mkdir()
        (agent_dir / "keybindings.json").write_text(json.dumps({
            "app.session.new": "ctrl+n", "app.session.tree": "ctrl+e",
            "app.session.fork": "ctrl+f", "app.session.resume": "ctrl+r",
        }))
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", str(ROOT), place, str(cwd / "agent")],
            cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color", "DISPLAY": "", "WAYLAND_DISPLAY": "", "TERMUX_VERSION": "", "PI_TUI_ESC_TIMEOUT": "10"},
        )
        output = bytearray()

        def until(needle, start=0, timeout=15):
            needles = needle if isinstance(needle, tuple) else (needle,)
            deadline = time.monotonic() + timeout
            while not any(value in output[start:] for value in needles) and time.monotonic() < deadline:
                if select.select([master], [], [], .2)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
            clean = re.sub(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)", b"", output[start:])
            assert any(value in output[start:] for value in needles), (threads, needle, process.poll(), clean[-6000:])

        try:
            until(b"faux-model")
            before = len(output)
            os.write(master, b"before\r")
            until(b'"type":"turn_end"', before)
            if shortcuts:
                before = len(output)
                os.write(master, b"draft kept during copy")
                time.sleep(.1)
                os.write(master, b"\x18")
                until(b"Copied last agent message to clipboard", before)
                copied = re.findall(rb"\x1b\]52;c;([A-Za-z0-9+/=]*)\x07", output[before:])
                assert copied and base64.b64decode(copied[-1]) == b"answer", (threads, copied)
                # Copying does not submit or replace the draft.
                os.write(master, b"\x01\x0b")
                for key, title in ((b"\x05", b"Session Tree"), (b"\x06", b"Fork from Message"), (b"\x12", b"Resume Session")):
                    before = len(output)
                    os.write(master, key)
                    until(title, before)
                    os.write(master, b"\x1b")
                    time.sleep(.1)
            html = cwd / "conversation.html"
            before = len(output)
            os.write(master, b"/export conversation.html\r")
            until(b"Session exported to: " + os.fsencode(html), before)
            payload = re.search(r'<script id="session-data" type="application/json">([A-Za-z0-9+/=]+)</script>', html.read_text())
            assert payload and "before" in base64.b64decode(payload.group(1)).decode()
            before = len(output)
            os.write(master, b"/export\r")
            # The generated filename makes the notice wrap at this terminal width.
            until(os.fsencode(cwd / "pi-session-"), before)
            assert b"Session exported to:" in output[before:]
            assert len(list(cwd.glob("pi-session-*.html"))) == 1
            jsonl = cwd / "nested" / "conversation copy.jsonl"
            before = len(output)
            os.write(master, b'/export "nested/conversation copy.jsonl"\r')
            until(b"Session exported to: " + os.fsencode(jsonl), before)
            assert any("before" in line for line in jsonl.read_text().splitlines())
            if shortcuts:
                before = len(output)
                os.write(master, b"\x06")
                until(b"Fork from Message", before)
                os.write(master, b"\r")
                until(b"Forked to new session", before)
                before = len(output)
                os.write(master, b" forked\r")
                until(b'"type":"turn_end"', before)
            before = len(output)
            os.write(master, b"preserved draft\x0e" if shortcuts else b"/new\r")
            until(b"New session started", before)
            before = len(output)
            os.write(master, b"hello\r")
            until(b"answer", before)
            os.write(master, b"/quit\r")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0, (threads, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original, threads
            assert not stderr, (threads, stderr.decode(errors="replace"))
            paths = re.findall(rb'\{"type":"factory","cwd":"[^"]+","sessionFile":"([^"]+)"', output)
            expected_sessions = 3 if shortcuts else 2
            assert len(paths) == expected_sessions and len(set(paths)) == expected_sessions, (threads, paths, bytes(output[:1200]))
            assert output.count(b'"reason":"new"') == 1, (threads, bytes(output[:1500]))
            files = list(cwd.glob("*.jsonl"))
            assert len(files) == expected_sessions and {os.fsencode(file) for file in files} == set(paths), (threads, files, paths)
            histories = {os.fsencode(file): [json.loads(line) for line in file.read_text().splitlines()] for file in files}
            exported = [json.loads(line) for line in jsonl.read_text().splitlines()]
            assert exported[0]["id"] == histories[paths[0]][0]["id"]
            assert exported[1:] == histories[paths[0]][1:]
            assert any(entry.get("type") == "message" and "before" in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
            assert any(entry.get("type") == "message" and "hello" in json.dumps(entry) for entry in histories[paths[-1]]), (threads, histories)
            assert all("hello" not in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
            assert all("draft kept during copy" not in json.dumps(entry) for history in histories.values() for entry in history), (threads, histories)
            if shortcuts:
                assert any("before forked" in json.dumps(entry) for entry in histories[paths[1]]), (threads, histories)
                assert all("before forked" not in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
                assert any("preserved drafthello" in json.dumps(entry) for entry in histories[paths[-1]]), (threads, histories)
                assert all("preserved draft" not in json.dumps(entry) for entry in histories[paths[0]]), (threads, histories)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads} {'shortcuts' if shortcuts else 'slash commands'}: HTML/JSONL export, isolated histories, terminal restore")


for threads in (1, 4):
    scenario(threads)
    scenario(threads, shortcuts=True)
