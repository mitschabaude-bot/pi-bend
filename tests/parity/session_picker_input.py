#!/usr/bin/env python3
"""Compare pi and pi-bend's /resume search editor in identical tmux terminals."""
import argparse
import json
import os
import tempfile
from pathlib import Path

from runner import Terminal


def session_files(root: Path):
    project = root / "project"
    sessions = root / "sessions"
    agent = root / "agent"
    for directory in (project, sessions, agent):
        directory.mkdir()
    for i in range(8):
        stamp = f"2025-01-01T00:00:{i:02d}Z"
        entries = [
            {"type": "session", "version": 3, "id": str(i), "timestamp": stamp, "cwd": str(project)},
            {"type": "message", "id": f"m{i}", "parentId": None, "timestamp": stamp,
             "message": {"role": "user", "content": f"question {i}", "timestamp": 1735689600000 + i * 1000}},
        ]
        (sessions / f"2025-01-01T00-00-{i:02d}-000Z_{i}.jsonl").write_text(
            "".join(json.dumps(entry) + "\n" for entry in entries)
        )
    return project, sessions, agent


def compare(label, upstream, bend):
    expected = upstream.screen(ansi=True).rstrip().splitlines()
    actual = bend.screen(ansi=True).rstrip().splitlines()
    if expected == actual:
        print(f"{label}: MATCH")
        return True
    print(f"{label}: DIFF")
    for i in range(max(len(expected), len(actual))):
        left = expected[i] if i < len(expected) else "<missing>"
        right = actual[i] if i < len(actual) else "<missing>"
        if left != right:
            print(f"  line {i}: pi={left!r}\n          bend={right!r}")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", required=True, type=Path)
    parser.add_argument("--focused", action="store_true", help="binary takes the focused picker fixture arguments")
    args = parser.parse_args()
    os.environ["PARITY_TMUX"] = f"pi-picker-input-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix="pi-picker-input-") as directory:
        root = Path(directory)
        project, sessions, agent = session_files(root)
        env = {"PATH": os.environ["PATH"], "HOME": str(root), "TERM": "xterm-256color",
               "PI_CODING_AGENT_DIR": str(agent), "FORCE_COLOR": "1"}
        bend_args = ([str(args.bend.resolve()), str(project), str(sessions), str(agent), str(sessions), str(root)]
                     if args.focused else [str(args.bend.resolve()), "--resume", "--session-dir", str(sessions)])
        upstream = Terminal("upstream-picker", ["pi", "--resume", "--session-dir", str(sessions)], env, project)
        bend = Terminal("bend-picker", bend_args, env, project)
        try:
            if upstream.wait("question 7", 20) is None or bend.wait("question 7", 20) is None:
                raise RuntimeError("picker did not reach its populated frame")
            ok = compare("initial", upstream, bend)
            steps = [
                ("type query", "keys", "question"),
                ("move to start", "key", "C-a"),
                ("insert at start", "keys", "x"),
                ("erase at start", "key", "BSpace"),
                ("move to end", "key", "C-e"),
                ("move left", "key", "Left"),
                ("insert in middle", "keys", "z"),
                ("erase word", "key", "C-w"),
                ("insert Unicode", "keys", "👩🏽‍💻漢"),
                ("erase Unicode cluster", "key", "BSpace"),
                ("bracketed paste", "keys", "\x1b[200~two words\x1b[201~"),
            ]
            for label, method, value in steps:
                getattr(upstream, method)(value)
                getattr(bend, method)(value)
                if label == "erase word":
                    print("word edit visible after:", upstream.wait(r"^> n", 5), bend.wait(r"^> n", 5))
                upstream.settle(0.05, 2)
                bend.settle(0.05, 2)
                ok = compare(label, upstream, bend) and ok
            if not ok:
                raise SystemExit(1)
        finally:
            upstream.close()
            bend.close()


if __name__ == "__main__":
    main()
