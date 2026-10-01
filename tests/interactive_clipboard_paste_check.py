#!/usr/bin/env python3
"""Compare mounted Ctrl+V image paste and text fallback with pinned pi."""
import argparse
import base64
import json
import os
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_PASTE_CLI", ROOT / "build/pi-cli")).resolve()
PIXEL = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")
XCLIP = """#!/bin/sh
if [ "$3" = "-t" ] && [ "$4" = "TARGETS" ]; then
  if [ -f "$HOME/image-mode" ]; then printf 'image/png\\n'; else printf 'UTF8_STRING\\n'; fi
elif [ "$3" = "-t" ] && [ "$4" = "image/png" ]; then
  cat "$HOME/pixel.png"
elif [ "$3" = "-out" ]; then
  printf 'clipboard words'
else
  exit 1
fi
"""


def scenario():
    return {
        "name": "clipboard-paste", "args": MODEL, "timeout": 15,
        "files": {"bin/xclip": XCLIP, "home/pixel.png": PIXEL},
        "executables": ["bin/xclip"], "tool_bin": "bin", "env": {"DISPLAY": ":99"},
        "turns": [{"text": "TEXT-DONE"}, {"text": "IMAGE-DONE"}],
        "steps": [
            ("wait", READY, "startup"), ("settle", .5),
            ("key", "C-v"), ("wait", "clipboard words", "text-paste"), ("snap", "text-editor"),
            ("keys", " question"), ("key", "Enter"),
            ("wait", "TEXT-DONE", "text-answer"), ("settle", .3),
            ("write", "home/image-mode", "yes"),
            ("key", "C-v"), ("wait", "pi-clipboard-", "image-paste"), ("snap", "image-editor"),
            ("key", "Enter"), ("wait", "IMAGE-DONE", "image-answer"),
        ],
    }


def editor_text(screen):
    lines = screen.splitlines()
    borders = [i for i, line in enumerate(lines) if line.startswith("─") and len(line) > 40]
    assert len(borders) >= 2, screen[-700:]
    return "\n".join(lines[borders[-2] + 1:borders[-1]]).strip()


def observations(result):
    assert all(value is not None for value in result["timings"].values()), result["timings"]
    requests = json.loads(result["requests"])
    assert len(requests) == 2, len(requests)
    user_texts = [request["body"]["input"][-1]["content"][0]["text"] for request in requests]
    return {
        "text-editor": editor_text(result["snaps"]["text-editor"]),
        "image-editor": editor_text(result["snaps"]["image-editor"]),
        "request-texts": user_texts,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true")
    args = parser.parse_args()
    upstream = observations(run_side("pi", [shutil.which("pi") or "pi"], scenario(), False))
    expected = {"text-editor": "clipboard words", "image-editor": "/tmp/pi-clipboard-<uuid>.png",
                "request-texts": ["clipboard words question", "/tmp/pi-clipboard-<uuid>.png"]}
    assert upstream == expected, (upstream, expected)
    print("pi: Ctrl+V text fallback, image path, and following requests pass", flush=True)
    if args.pi_only:
        return
    assert BINARY.is_file(), f"Native binary is missing: {BINARY}"
    for threads in ("1", "4"):
        os.environ["BEND_THREADS"] = threads
        native = observations(run_side("bend", [str(BINARY)], scenario(), False))
        assert native == upstream, (threads, native, upstream)
        print(f"native {threads}: Ctrl+V paste matches pi", flush=True)


if __name__ == "__main__":
    main()
