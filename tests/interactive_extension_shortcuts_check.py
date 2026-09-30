#!/usr/bin/env python3
"""Exercise native shortcut dispatch through the terminal against pinned pi.

Build with: BEND_INCREMENTAL=0 BEND_TUS=8 sh scripts/build-cli.sh build/pi-shortcuts-candidate tests/fixtures/extension-shortcuts.bend
"""
import os
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_SHORTCUT_CLI", ROOT / "build/pi-shortcuts-candidate")).resolve()


def scenario(extension):
    return {
        "name": "extension-shortcuts",
        "args": MODEL + ["--extension", str(extension)],
        "files": {"home/.pi/agent/keybindings.json": '{"app.tools.expand":"alt+o","app.editor.external":"alt+g"}'},
        "timeout": 15,
        "steps": [
            ("wait", READY, "startup"), ("settle", .3),
            ("key", "C-v"), ("wait", "SHORTCUT-OK", "immediate"),
            ("key", "C-u"), ("key", "C-o"),
            ("keys", "draft"), ("wait", "draft", "while-pending"),
            # Pi's setEditorText updates state without requesting a redraw.
            ("settle", 1.2), ("keys", "!"), ("wait", "ASYNC-OK!", "completion"),
            ("key", "C-u"), ("key", "C-g"),
            ("wait", "Shortcut handler error: shortcut fixture failure", "error"),
            ("keys", "/reload"), ("key", "Enter"),
            ("wait", "Reloaded keybindings", "reload"),
            ("key", "C-v"), ("wait", "SHORTCUT-OK", "after-reload"),
            ("key", "C-u"), ("keys", "/new"), ("key", "Enter"),
            ("wait", "New session started", "new-session"),
            ("key", "C-v"), ("wait", "SHORTCUT-OK", "after-new"),
            ("key", "C-u"), ("key", "C-d"), ("wait", "shell\\$", "exit"),
        ],
    }


def check(result, name):
    timings = result["timings"]
    assert all(value is not None for value in timings.values()), (name, timings)
    assert timings["while-pending"] < .5, (name, "handler blocked input", timings)
    assert not result["requests"], (name, "shortcut sent a model request")
    print(name, {key: round(value * 1000) for key, value in timings.items()}, flush=True)


def reserved(extension):
    return {
        "name": "extension-shortcuts-reserved",
        "args": MODEL + ["--extension", str(extension)],
        "timeout": 15,
        "steps": [
            ("wait", READY, "startup"), ("settle", .3),
            ("key", "C-o"), ("keys", "draft"), ("wait", "draft", "while-pending"),
            ("settle", 1.2), ("keys", "!"), ("wait", "draft!", "reserved"),
            ("key", "C-u"), ("key", "C-d"), ("wait", "shell\\$", "exit"),
        ],
    }


def main():
    upstream = ROOT / "tests/fixtures/extension-shortcuts.ts"
    native = ROOT / "tests/fixtures/extension-shortcuts.bend"
    check(run_side("pi", [shutil.which("pi") or "pi"], scenario(upstream), False), "pi")
    check(run_side("pi", [shutil.which("pi") or "pi"], reserved(upstream), False), "pi reserved")
    for threads in ("1", "4"):
        os.environ["BEND_THREADS"] = threads
        check(run_side("bend", [str(BINARY)], scenario(native), False), f"native {threads}")
        check(run_side("bend", [str(BINARY)], reserved(native), False), f"native {threads} reserved")


if __name__ == "__main__":
    main()
