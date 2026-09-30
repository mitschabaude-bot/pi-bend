#!/usr/bin/env python3
"""Check live keybinding reload through the mounted terminal UI against pinned pi.

Run the upstream oracle with --pi-only. The candidate defaults to
build/pi-keybindings-reload (override with PI_BEND_KEYBINDINGS_RELOAD_CLI).
"""
import argparse
import json
import os
import re
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_KEYBINDINGS_RELOAD_CLI", ROOT / "build/pi-keybindings-reload")).resolve()
BINDINGS = json.dumps({
    "app.model.select": "alt+m",
    "tui.select.down": "alt+j",
    "tui.select.cancel": "alt+k",
    "tui.editor.cursorLeft": "alt+q",
    "tui.editor.undo": "alt+u",
    "tui.editor.historyPrevious": "alt+h",
})


def scenario():
    return {
        "name": "keybindings-live-reload",
        "args": MODEL,
        "timeout": 15,
        "steps": [
            ("wait", READY, "startup"), ("settle", .5),
            ("keys", "remember-this"), ("key", "Enter"),
            ("wait", "script exhausted", "response"), ("settle", .3),
            ("key", "C-l"), ("settle", .2), ("snap", "initial-model"),
            ("key", "Escape"), ("settle", .5),
            ("write", "home/.pi/agent/keybindings.json", BINDINGS),
            ("keys", "/reload"), ("settle", .2), ("key", "Enter"),
            ("wait", "Reloaded keybindings", "reload"), ("settle", .2),
            ("key", "C-l"), ("settle", .2), ("snap", "old-model-key"),
            ("key", "M-m"), ("settle", .2), ("snap", "new-model-key"),
            ("key", "Down"), ("settle", .2), ("snap", "old-down-key"),
            ("key", "M-j"), ("settle", .2), ("snap", "new-down-key"),
            ("key", "Escape"), ("settle", .3), ("snap", "old-cancel-key"),
            ("key", "M-k"), ("settle", .2), ("snap", "new-cancel-key"),
            ("keys", "ab"), ("key", "Left"), ("keys", "X"),
            ("settle", .1), ("snap", "old-left-key"),
            ("key", "M-q"), ("settle", .1), ("keys", "Y"),
            ("settle", .1), ("snap", "new-left-key"),
            ("key", "M-u"), ("settle", .1), ("snap", "undo"),
            ("key", "C-c"), ("settle", .5),
            ("key", "M-h"), ("settle", .1), ("snap", "history"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "/hotkeys"), ("settle", .2), ("key", "Enter"),
            ("settle", .3), ("snap-history", "hotkeys"),
        ],
    }


def model_index(screen):
    match = re.search(r"\((\d+)/\d+\)", screen)
    return int(match.group(1)) if match else None


def editor_text(screen):
    lines = screen.splitlines()
    borders = [index for index, line in enumerate(lines) if line.startswith("─") and len(line) > 40]
    assert len(borders) >= 2, screen[-700:]
    return "\n".join(lines[borders[-2] + 1:borders[-1]]).strip()


def observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    screens = result["snaps"]
    observed = {
        "initial-model": model_index(screens["initial-model"]),
        "old-model-key": model_index(screens["old-model-key"]),
        "new-model-key": model_index(screens["new-model-key"]),
        "old-down-key": model_index(screens["old-down-key"]),
        "new-down-key": model_index(screens["new-down-key"]),
        "old-cancel-key": model_index(screens["old-cancel-key"]),
        "new-cancel-key": model_index(screens["new-cancel-key"]),
        "old-left-key": editor_text(screens["old-left-key"]),
        "new-left-key": editor_text(screens["new-left-key"]),
        "undo": editor_text(screens["undo"]),
        "history": editor_text(screens["history"]),
        "hotkeys": tuple(key in screens["hotkeys"] for key in ("Alt+M", "Alt+Q", "Alt+U")),
        "requests": len(json.loads(result["requests"])),
    }
    expected = {
        "initial-model": 1, "old-model-key": None, "new-model-key": 1,
        "old-down-key": 1, "new-down-key": 2, "old-cancel-key": 2,
        "new-cancel-key": None, "old-left-key": "abX",
        "new-left-key": "abYX", "undo": "abX", "history": "remember-this",
        "hotkeys": (True, True, True), "requests": 1,
    }
    assert observed == expected, {key: (observed[key], value) for key, value in expected.items() if observed[key] != value}
    return observed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true", help="check the pinned pi oracle without the candidate binary")
    args = parser.parse_args()
    upstream = observations(run_side("pi", [shutil.which("pi") or "pi"], scenario(), False))
    print("pi: live reload, editor, selector, and /hotkeys checks pass", flush=True)
    if args.pi_only:
        return
    assert BINARY.is_file(), f"Candidate binary is missing: {BINARY}"
    for threads in ("1", "4"):
        os.environ["BEND_THREADS"] = threads
        native = observations(run_side("bend", [str(BINARY)], scenario(), False))
        assert native == upstream, (threads, native, upstream)
        print(f"native {threads}: live keybindings match pi", flush=True)


if __name__ == "__main__":
    main()
