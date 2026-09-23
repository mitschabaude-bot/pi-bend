"""Compare native main-screen effects and state with the pinned pi-mono (tests/upstream_pin.py).

Set BEND_COMPILER to a current bend2/main.ts when the installed compiler lacks
recent process constructors. Setting `BEND_MAIN_SCREEN_NATIVE` also compares a prebuilt binary named by
BEND_MAIN_SCREEN_NATIVE; it never starts a build itself.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("BEND_COMPILER", "/home/agent/code/pi-bend-tls/build/bend-process-files/bend2/main.ts"))


def run(command, env=None):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, check=True)
    return [json.loads(line) for line in result.stdout.splitlines()]


def oracle_env():
    env = os.environ.copy()
    if not env.get("NODE_PATH"):
        for candidate in (
            ROOT.parent / "pi-mono/node_modules",
            ROOT.parent / "pi-bend-tui-text/build/text-reference/node_modules",
            ROOT.parent / "pi-bend-tui-ansi/build/ansi-reference/node_modules",
        ):
            if (candidate / "get-east-asian-width").exists():
                env["NODE_PATH"] = str(candidate)
                break
    return env


def compare(label, actual, expected):
    if len(actual) != len(expected):
        raise AssertionError(f"{label}: {len(actual)} reports versus {len(expected)}")
    for index, (got, want) in enumerate(zip(actual, expected, strict=True)):
        if got != want:
            raise AssertionError(f"{label}: frame {index // 2 + 1} {'effects' if index % 2 == 0 else 'state'} differs: {got!r} != {want!r}")
    print(f"{label}: {len(actual) // 2} frames, effects and state agree")


if __name__ == "__main__":
    oracle = run(["bun", "tests/tui-main-screen-oracle.ts"], oracle_env())
    bend = run(["bun", str(COMPILER), "tests/tui-main-screen-check.bend"])
    compare("Bun", bend, oracle)
    native = os.environ.get("BEND_MAIN_SCREEN_NATIVE")
    if native:
        compare("native", run([native]), oracle)
