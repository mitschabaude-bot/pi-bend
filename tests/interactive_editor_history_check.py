#!/usr/bin/env python3
"""Compare mounted editor history across session load, reload, new, and resume."""
import argparse
import json
import os
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_HISTORY_CLI", ROOT / "build/pi-cli")).resolve()
KEYS = json.dumps({"tui.editor.historyPrevious": "alt+h", "tui.editor.historyNext": "alt+l"})


def session_file():
    entries = [
        {"type": "session", "version": 3, "id": "history-seed", "timestamp": "2025-01-01T00:00:00Z", "cwd": "<root>/project"},
        {"type": "message", "id": "history-first", "parentId": None, "timestamp": "2025-01-01T00:00:01Z", "message": {"role": "user", "content": "seed first", "timestamp": 1735689601000}},
        {"type": "message", "id": "history-second", "parentId": "history-first", "timestamp": "2025-01-01T00:00:02Z", "message": {"role": "user", "content": [{"type": "text", "text": "seed "}, {"type": "text", "text": "second"}], "timestamp": 1735689602000}},
    ]
    return "".join(json.dumps(entry) + "\n" for entry in entries)


def scenario():
    return {
        "name": "editor-history-session-switch",
        "args": MODEL + ["--session", "seed.jsonl"],
        "files": {"project/seed.jsonl": session_file(), "home/.pi/agent/keybindings.json": KEYS},
        "timeout": 15,
        "steps": [
            ("wait", READY, "startup"), ("settle", .5),
            ("key", "M-h"), ("settle", .15), ("snap", "startup-latest"),
            ("key", "M-h"), ("settle", .15), ("snap", "startup-older"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "live newer"), ("key", "Enter"),
            ("wait", "script exhausted", "response"), ("settle", .3),
            ("keys", "/reload"), ("settle", .2), ("key", "Enter"),
            ("wait", "Reloaded keybindings", "reload"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "after-reload"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "/new"), ("settle", .2), ("key", "Enter"),
            ("wait", "New session started", "new"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "after-new"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "new session prompt"), ("key", "Enter"), ("settle", .4),
            ("keys", "/resume"), ("settle", .2), ("key", "Enter"),
            ("wait", "Resume Session", "picker"), ("settle", .2), ("snap", "picker"),
            ("key", "Down"), ("settle", .15),
            ("key", "Enter"), ("wait", "Resumed session", "resumed"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "after-resume"),
            ("key", "M-h"), ("settle", .15), ("snap", "after-resume-older"),
        ],
    }


def editor_text(screen):
    lines = screen.splitlines()
    borders = [i for i, line in enumerate(lines) if line.startswith("─") and len(line) > 40]
    assert len(borders) >= 2, screen[-700:]
    return "\n".join(lines[borders[-2] + 1:borders[-1]]).strip()


def observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    screens = result["snaps"]
    return {name: editor_text(screens[name]) for name in (
        "startup-latest", "startup-older", "after-reload", "after-new",
        "after-resume", "after-resume-older"
    )}


def follow_up_scenario():
    return {
        "name": "editor-history-follow-up", "args": MODEL, "timeout": 15,
        "files": {"home/.pi/agent/keybindings.json": json.dumps({
            "tui.editor.historyPrevious": "alt+h", "tui.editor.undo": "alt+u",
        })},
        "turns": [{"text": "IDLE-DONE"},
                  {"text": "STREAMING " * 80 + "STREAM-DONE", "chunks": 100, "delay_ms": 20},
                  {"text": "FOLLOW-UP-DONE"}],
        "steps": [
            ("wait", READY, "startup"), ("settle", .5),
            ("keys", "/new"), ("key", "M-Enter"),
            ("wait", "New session started", "new"), ("settle", .2),
            ("key", "M-u"), ("settle", .15), ("snap", "idle-command-undo"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "idle prompt"), ("key", "M-Enter"),
            ("wait", "IDLE-DONE", "idle-answer"), ("settle", .3),
            ("key", "M-h"), ("settle", .15), ("snap", "idle-history"),
            ("key", "C-c"), ("settle", .5),
            ("keys", "stream prompt"), ("key", "Enter"),
            ("wait", "STREAMING", "streaming"),
            ("keys", "follow-up prompt"), ("key", "M-Enter"),
            ("wait", "FOLLOW-UP-DONE", "follow-up-answer"), ("settle", .3),
            ("key", "M-h"), ("settle", .15), ("snap", "follow-up-history"),
            ("key", "M-h"), ("settle", .15), ("snap", "preceding-history"),
        ],
    }


def follow_up_observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    observed = {name: editor_text(result["snaps"][name]) for name in (
        "idle-command-undo", "idle-history", "follow-up-history", "preceding-history",
    )}
    observed["requests"] = len(json.loads(result["requests"]))
    return observed


def bash_history_scenario():
    return {
        "name": "editor-bash-history", "args": MODEL, "timeout": 15,
        "files": {"home/.pi/agent/keybindings.json": json.dumps({"tui.editor.historyPrevious": "alt+h"})},
        "steps": [
            ("wait", READY, "startup"), ("settle", .5),
            ("keys", "!  echo first-bash"), ("key", "Enter"),
            ("wait", "\\n first-bash\\n", "first-bash"), ("settle", .2),
            ("keys", "!!  echo second-bash"), ("key", "Enter"),
            ("wait", "\\n second-bash\\n", "second-bash"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "latest"),
            ("key", "M-h"), ("settle", .15), ("snap", "older"),
            ("key", "C-c"), ("settle", .2),
            ("keys", "   "), ("key", "Enter"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "after-blank"),
            ("key", "C-c"), ("settle", .2),
            ("keys", "!  sleep 10"), ("key", "Enter"),
            ("wait", "\\$ sleep 10", "running"),
            ("keys", "!!  echo rejected-busy"), ("key", "Enter"),
            ("wait", "A bash command is already running", "busy"),
            ("snap", "busy-editor"),
            ("key", "Escape"), ("wait", "\\(cancelled\\)", "cancelled"), ("settle", .2),
            ("key", "C-c"), ("settle", .2),
            ("key", "M-h"), ("settle", .15), ("snap", "after-busy"),
            ("key", "M-h"), ("settle", .15), ("snap", "before-busy"),
        ],
    }


def bash_history_observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    return {name: editor_text(result["snaps"][name]) for name in (
        "latest", "older", "after-blank", "busy-editor", "after-busy", "before-busy",
    )}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true")
    args = parser.parse_args()
    upstream = observations(run_side("pi", [shutil.which("pi") or "pi"], scenario(), False))
    expected = {
        "startup-latest": "seed second", "startup-older": "seed first",
        "after-reload": "live newer", "after-new": "live newer",
        "after-resume": "live newer", "after-resume-older": "seed second",
    }
    assert upstream == expected, (upstream, expected)
    print("pi: session history passes startup, reload, new, and resume", flush=True)
    follow_up = follow_up_observations(run_side("pi", [shutil.which("pi") or "pi"], follow_up_scenario(), False))
    assert follow_up == {
        "idle-command-undo": "/new", "idle-history": "idle prompt",
        "follow-up-history": "follow-up prompt", "preceding-history": "stream prompt", "requests": 3,
    }, follow_up
    print("pi: idle submission and streaming follow-up history pass", flush=True)
    bash_history = bash_history_observations(run_side("pi", [shutil.which("pi") or "pi"], bash_history_scenario(), False))
    assert bash_history == {
        "latest": "!!  echo second-bash", "older": "!  echo first-bash",
        "after-blank": "!!  echo second-bash", "busy-editor": "!!  echo rejected-busy",
        "after-busy": "!  sleep 10", "before-busy": "!!  echo second-bash",
    }, bash_history
    print("pi: accepted, blank, and busy shell history pass", flush=True)
    if args.pi_only:
        return
    assert BINARY.is_file(), f"Candidate binary is missing: {BINARY}"
    for threads in ("1", "4"):
        os.environ["BEND_THREADS"] = threads
        native = observations(run_side("bend", [str(BINARY)], scenario(), False))
        assert native == upstream, (threads, native, upstream)
        native_follow_up = follow_up_observations(run_side("bend", [str(BINARY)], follow_up_scenario(), False))
        assert native_follow_up == follow_up, (threads, native_follow_up, follow_up)
        native_bash_history = bash_history_observations(run_side("bend", [str(BINARY)], bash_history_scenario(), False))
        assert native_bash_history == bash_history, (threads, native_bash_history, bash_history)
        print(f"native {threads}: editor history matches pi", flush=True)


if __name__ == "__main__":
    main()
