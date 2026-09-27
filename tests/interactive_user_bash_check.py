#!/usr/bin/env python3
"""Interactive user_bash failure handling (#9068), overrides and persisted results.

Run with: uv run --with pyte tests/interactive_user_bash_check.py
"""
import codecs
import errno
import fcntl
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

import pyte

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_USER_BASH_RUN", ROOT / "build/interactive-user-bash-current")).resolve()


def scenario(threads):
    with tempfile.TemporaryDirectory(prefix="pi-user-bash-") as place:
        cwd = Path(place)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 150, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(BINARY), "--threads", str(threads), "--", "bash", str(ROOT), place, str(cwd / "agent")],
            cwd=cwd, stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color", "PI_FAUX_API_KEY": "faux-key"},
        )
        screen = pyte.Screen(150, 24)
        terminal = pyte.Stream(screen)
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        output = bytearray()

        def until(predicate, description):
            deadline = time.monotonic() + 20
            while not predicate() and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    output.extend(chunk)
                    terminal.feed(decoder.decode(chunk))
            assert predicate(), (threads, description, process.poll(), "\n".join(screen.display))

        def visible(text):
            until(lambda: any(text in row for row in screen.display), text)

        def submit(text):
            os.write(master, text.encode() + b"\r")

        def events():
            path = cwd / "bash-events.jsonl"
            return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

        def export(name):
            submit(f"/export {name}")
            until(lambda: (cwd / name).exists(), f"export {name}")
            visible(name)
            return [json.loads(line) for line in (cwd / name).read_text().splitlines()]

        try:
            visible("faux-model")
            for prefix in ("!", "!!"):
                before = len(events())
                submit(prefix + "touch rejected")
                until(lambda: len(events()) == before + 1, "rejected event")
                visible("Routing failed")
                assert not (cwd / "rejected").exists()
            rejected = export("rejected.jsonl")
            assert not any(record.get("message", {}).get("command") == "touch rejected" for record in rejected)
            for index, prefix in enumerate(("!", "!!")):
                before = len(events())
                submit(prefix + "touch overridden")
                until(lambda: len(events()) == before + 1, "override event")
                visible("EXTENSION_RESULT")
                rows = export(f"override-{index}.jsonl")
                messages = [row["message"] for row in rows if row.get("message", {}).get("command") == "touch overridden"]
                assert len(messages) == index + 1, messages
                assert messages[-1]["output"] == "EXTENSION_RESULT", messages
                assert messages[-1]["excludeFromContext"] == (prefix == "!!"), messages
                assert not (cwd / "overridden").exists()
            submit("!touch operations")
            visible("CUSTOM_OPERATIONS")
            rows = export("operations.jsonl")
            custom = next(row["message"] for row in rows if row.get("message", {}).get("command") == "touch operations")
            assert custom["output"] == "CUSTOM_OPERATIONS" and custom["exitCode"] == 0, custom
            assert not (cwd / "operations").exists()
            submit("!touch passed")
            until(lambda: (cwd / "passed").exists(), "local execution")
            rows = export("passed.jsonl")
            assert any(row.get("message", {}).get("command") == "touch passed" for row in rows)
            observed = events()
            assert [event["command"] for event in observed] == ["touch rejected", "touch rejected", "touch overridden", "touch overridden", "touch operations", "touch passed"], observed
            assert [event["excludeFromContext"] for event in observed] == [False, True, False, True, False, False], observed
            assert all(event["cwd"] == place for event in observed), observed
            submit("after interception")
            visible("answer")
            assert b"A bash command is already running" not in output
            submit("/quit")
            stderr = process.communicate(timeout=20)[1]
            assert process.returncode == 0 and not stderr, (process.returncode, stderr.decode(errors="replace"))
            assert termios.tcgetattr(slave) == original
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
    print(f"native{threads}: !/!! fail closed, overrides, custom operations, pass-through, history, next prompt")


for threads in (1, 4):
    scenario(threads)
