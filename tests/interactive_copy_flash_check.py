#!/usr/bin/env python3
"""Compare Ctrl+X copy feedback in both TUI modes and /copy with pinned pi."""
import argparse
import difflib
from itertools import islice
import os
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_COPY_CLI", ROOT / "build/pi-cli")).resolve()
ANSWER = "copy-flash-answer"
DRAFT = "draft kept during copy"
XCLIP = '#!/bin/sh\ncat > "$HOME/clipboard.txt"\n'
FRAMES = ("before-copy", "flash", "expired", "slash")


def scenario(fullscreen):
    return {
        "name": "copy-flash-fullscreen" if fullscreen else "copy-flash-regular",
        "args": MODEL + (["--tui-mode", "fullscreen"] if fullscreen else []), "timeout": 15,
        "files": {"bin/xclip": XCLIP}, "executables": ["bin/xclip"],
        "tool_bin": "bin", "env": {"DISPLAY": ":99"},
        "turns": [{"text": ANSWER}],
        "steps": [
            ("wait", READY, "startup"), ("wait", "Warning: fd not found", "ready"),
            ("settle", .3), ("keys", "hello"), ("key", "Enter"),
            ("wait", ANSWER, "answer"), ("settle", .3),
            ("keys", DRAFT), ("settle", .1), ("snap", "before-copy"),
            ("key", "C-x"),
            ("wait", "Copied!" if fullscreen else "Copied last agent message to clipboard", "copy-feedback"),
            ("snap", "flash"), ("file", "home/clipboard.txt", "shortcut-clipboard"),
            ("settle", 1.2), ("snap", "expired"),
            ("key", "C-a"), ("key", "C-k"),
            ("keys", "/copy"), ("key", "Enter"),
            ("wait", "Copied last agent message to clipboard", "slash-status"),
            ("settle", .3),
            ("snap", "slash"), ("file", "home/clipboard.txt", "slash-clipboard"),
        ],
    }


def observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    snaps = result["snaps"]
    return {
        "flash": "Copied!" in snaps["flash"],
        "flash-expired": "Copied!" not in snaps["expired"],
        "shortcut-status": "Copied last agent message to clipboard" in snaps["flash"],
        "draft-before": DRAFT in snaps["before-copy"],
        "draft-during": DRAFT in snaps["flash"],
        "draft-after": DRAFT in snaps["expired"],
        "shortcut-clipboard": snaps["shortcut-clipboard"],
        "slash-status": "Copied last agent message to clipboard" in snaps["slash"],
        "slash-clipboard": snaps["slash-clipboard"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true")
    parser.add_argument("--lanes", default="1,4", help="native thread counts, comma-separated")
    args = parser.parse_args()
    if not args.pi_only:
        assert BINARY.is_file(), BINARY
    for fullscreen in (True, False):
        mode = "fullscreen" if fullscreen else "regular"
        upstream_run = run_side("pi", [shutil.which("pi") or "pi"], scenario(fullscreen), False)
        upstream = observations(upstream_run)
        expected = {
            "flash": fullscreen, "flash-expired": True, "shortcut-status": not fullscreen,
            "draft-before": True, "draft-during": True, "draft-after": True,
            "shortcut-clipboard": ANSWER, "slash-status": True,
            "slash-clipboard": ANSWER,
        }
        assert upstream == expected, (mode, upstream, expected)
        print(f"pi {mode}: Ctrl+X and /copy feedback, clipboard, and draft pass", flush=True)
        if args.pi_only:
            continue
        for threads in args.lanes.split(","):
            os.environ["BEND_THREADS"] = threads
            native_run = run_side("bend", [str(BINARY)], scenario(fullscreen), False)
            native = observations(native_run)
            assert native == upstream, (mode, threads, native, upstream)
            for name in FRAMES:
                for capture in (name, name + ".color"):
                    actual, reference = native_run["snaps"][capture], upstream_run["snaps"][capture]
                    difference = "".join(islice(difflib.unified_diff(
                        reference.splitlines(keepends=True), actual.splitlines(keepends=True),
                        fromfile="pi", tofile="native"), 24))
                    assert actual == reference, (mode, threads, capture, difference)
            print(f"native {threads} {mode}: Ctrl+X and /copy payloads, frames, and colors match pi", flush=True)


if __name__ == "__main__":
    main()
