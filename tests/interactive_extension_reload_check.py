#!/usr/bin/env python3
"""Compare native factory replacement through /reload with pinned pi.

Build the candidate with tests/fixtures/reload-extension.bend linked, then
set PI_BEND_EXTENSION_RELOAD_CLI to its path. --pi-only runs the oracle.
"""
import argparse
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


def checked(label, argv, native):
    result = run_side(label, argv, scenario(native), False)
    missing = [name for name, value in result["timings"].items() if value is None]
    assert not missing, (label, missing, result)
    print(f"{label}: initial factory and two reloads replace event and command registrations", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pi-only", action="store_true")
    args = parser.parse_args()
    checked("pi", [shutil.which("pi") or "pi"], False)
    if not args.pi_only:
        for threads in (1, 4):
            os.environ["BEND_THREADS"] = str(threads)
            checked("bend", [str(BINARY.resolve())], True)


if __name__ == "__main__":
    main()
