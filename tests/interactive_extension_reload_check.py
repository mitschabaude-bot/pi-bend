#!/usr/bin/env python3
"""Compare factory reload and immediate streaming-command dispatch with pinned pi.

Build the candidate with tests/fixtures/reload-extension.bend linked, then
set PI_BEND_EXTENSION_RELOAD_CLI to its path. --pi-only runs the oracle.
"""
import argparse
import json
import os
import shutil
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL, READY

ROOT = Path(__file__).resolve().parents[1]
EXTENSION = ROOT / "tests/fixtures/reload-extension.bend"
BINARY = Path(os.environ.get("PI_BEND_EXTENSION_RELOAD_CLI", ROOT / "build/pi-extension-reload"))
ORACLE = '''import fs from "node:fs";
export default function(pi) {
  const tag = fs.readFileSync("reload-tag.txt", "utf8");
  pi.on("session_start", (_, ctx) => ctx.ui.setStatus("reload-probe", "factory-" + tag));
  pi.registerCommand("reload-probe", {handler: (_, ctx) => ctx.ui.setStatus("reload-probe", "command-" + tag)});
}
'''


def scenario(native):
    files = {"project/reload-tag.txt": "one", "home/.pi/agent/trust.json": '{"<root>/project": true}'}
    if not native:
        files["project/.pi/extensions/reload.ts"] = ORACLE
    return {
        "name": "extension-factory-reload", "timeout": 20,
        "args": MODEL + (["-e", str(EXTENSION)] if native else []), "files": files,
        "steps": [
            ("wait", READY, "startup"), ("wait", "factory-one", "initial-start"), ("settle", .2),
            ("keys", "/reload-probe"), ("settle", .2), ("key", "Enter"), ("wait", "command-one", "initial-command"),
            ("write", "project/reload-tag.txt", "two"),
            ("keys", "/reload"), ("settle", .2), ("key", "Enter"), ("wait", "Reloaded keybindings", "reload"),
            ("wait", "factory-two", "reloaded-start"), ("settle", .2),
            ("keys", "/reload-probe"), ("settle", .2), ("key", "Enter"), ("wait", "command-two", "reloaded-command"),
            ("write", "project/reload-tag.txt", "three"),
            ("keys", "/reload"), ("settle", .2), ("key", "Enter"), ("wait", "factory-three", "second-start"), ("settle", .2),
            ("keys", "/reload-probe"), ("settle", .2), ("key", "Enter"), ("wait", "command-three", "second-command"),
        ],
    }


def streaming_scenario(native, follow_up=False):
    value = scenario(native)
    # Suppress unrelated startup resource listings in both implementations.
    value["files"]["home/.pi/agent/settings.json"] = '{"quietStartup": true}'
    value["name"] = "extension-command-during-streaming" + ("-follow-up" if follow_up else "")
    value["turns"] = [{"text": "STREAM-BEGIN " + "Still answering. " * 30 + "STREAM-END", "chunks": 40, "delay_ms": 100}, {"text": "AFTER-COMMAND"}]
    value["steps"] = [
        ("wait", READY, "startup"), ("wait", "factory-one", "initial-start"),
        ("keys", "start"), ("key", "Enter"), ("wait", "STREAM-BEGIN", "stream-start"),
        ("keys", "/reload-probe"), ("key", "M-Enter" if follow_up else "Enter"), ("wait", "command-one", "stream-command"),
        ("keys", "next"), ("key", "Enter"),
        ("wait", "STREAM-END", "stream-end"), ("wait", "AFTER-COMMAND", "next-answer"),
        ("settle", .3), ("snap", "next-answer"),
    ]
    return value


def checked(label, argv, native, streaming=False, follow_up=False):
    result = run_side(label, argv, streaming_scenario(native, follow_up) if streaming else scenario(native), False)
    missing = [name for name, value in result["timings"].items() if value is None]
    assert not missing, (label, missing)
    if streaming:
        assert len(json.loads(result["requests"])) == 2, (label, "extension command consumed a provider response")
        assert result["timings"]["stream-command"] < 1, (label, result["timings"])
        print(f"{label}: extension command runs during streaming without a provider request; next prompt succeeds", flush=True)
    else:
        print(f"{label}: initial factory and two reloads replace event and command registrations", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true")
    args = parser.parse_args()
    checked("pi", [shutil.which("pi") or "pi"], False)
    expected = [checked("pi", [shutil.which("pi") or "pi"], False, streaming=True, follow_up=mode) for mode in (False, True)]
    if not args.pi_only:
        for threads in (1, 4):
            os.environ["BEND_THREADS"] = str(threads)
            checked("bend", [str(BINARY.resolve())], True)
            for mode, oracle in zip((False, True), expected):
                actual = checked("bend", [str(BINARY.resolve())], True, streaming=True, follow_up=mode)
                assert actual["requests"] == oracle["requests"], (threads, mode, "provider requests")
                assert actual["snaps"] == oracle["snaps"], (threads, mode, "terminal frames")


if __name__ == "__main__":
    main()
