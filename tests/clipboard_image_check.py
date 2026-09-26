#!/usr/bin/env python3
"""Clipboard image paste: upstream clipboard-image.test.ts and
clipboard-image-bmp-conversion.test.ts (packages/coding-agent/test/clipboard-image.bend,
injected commands and native helper), clipboard-image-native-errors.test.ts
(packages/coding-agent/test/clipboard-paste.bend, with two supplements), and
clipboard-command.test.ts (packages/coding-agent/test/clipboard-command.bend,
native only: the Bun lane has no process spawning).

Build: for t in clipboard-image clipboard-paste; do
         bun build/bend-process-files/bend2/main.ts packages/coding-agent/test/$t.bend -o build/$t.js
         flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh packages/coding-agent/test/$t.bend build/$t-native; done
       flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh packages/coding-agent/test/clipboard-command.bend build/clipboard-command-native
"""
from upstream_pin import UPSTREAM
import hashlib
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for source, digest in [
    ("packages/coding-agent/test/clipboard-image.test.ts", "4625b5118a2e0ca50443be0fe5b554dd89b6259806711c399322068916965b80"),
    ("packages/coding-agent/test/clipboard-image-bmp-conversion.test.ts", "6695d300c4ba9da679b80d3e8902ffac2dd8b494be491db60d92a4cff541209b"),
    ("packages/coding-agent/test/clipboard-command.test.ts", "2960f8f315759db8f25f92fa9f62c65380beabfc1cbe6a167fe2d7ce555c6892"),
    ("packages/coding-agent/test/clipboard-image-native-errors.test.ts", "d3b3a03e68441be765e49e644d8921f8fdde33e61dd2d44dead5920157e0bf07"),
    ("packages/coding-agent/src/utils/clipboard-image.ts", "d0f228cbf7df4bd11bc0fd039c23049a8f2166b2e48a5df2e1a3e51723058904"),
]:
    assert hashlib.sha256((UPSTREAM / source).read_bytes()).hexdigest() == digest, source

NAMES = [f"readClipboardImage > {backend}: command image present={present} stops fallback"
         for backend in ["wayland", "x11"] for present in ["true", "false"]]
NAMES += [f"readClipboardImage > native X11 result {label} stops fallback" for label in ["png", "null", "empty"]]
NAMES += [f"readClipboardImage > Wayland: falls back to X11 after {failure}" for failure in ["missing module", "unavailable display"]]
NAMES += ["readClipboardImage > WSL: tries PowerShell before a broken native X11 bridge"]
NAMES += [f"readClipboardImage > {platform}: reads native image {label} once"
          for platform in ["darwin", "win32"] for label in ["png", "null", "empty", "undefined"]]
NAMES += ["readClipboardImage > returns null without a native helper"]
NAMES += [f"readClipboardImage > {platform}: propagates native transfer errors without fallback" for platform in ["linux", "win32"]]
NAMES += ["readClipboardImage > Termux does not read image clipboards"]
NAMES += [f"readClipboardImage BMP conversion > {platform}: converts command/native BMP to PNG" for platform in ["linux", "win32"]]
EXPECTED = [f"PASS {name}" for name in NAMES]
PASTE = [f"PASS {name}" for name in [
    "native image errors abort paste without reading text or changing the editor",
    "native supplement > an image is written to the temp directory and inserted by its path",
    "native supplement > without an image the clipboard's text is inserted"]]
COMMANDS = [f"PASS clipboard commands > {name}" for name in [
    "preserves binary output and distinguishes empty success from failure",
    "sends Unicode input to clipboard writers",
    "times out without blocking the event loop",
    "rejects output above the buffer limit"]]


def check(label, command, threads=None, expected=EXPECTED):
    env = dict(os.environ)
    if threads:
        env["BEND_THREADS"] = threads
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
    lines = [line for line in result.stdout.splitlines() if line.startswith(("PASS ", "FAIL "))]
    assert result.returncode == 0 and lines == expected, (label, result.returncode, lines, result.stderr[-2000:])
    print(f"{label}: {len(lines)} pass")


check("Bun", ["bun", "build/clipboard-image.js"])
check("native1", ["build/clipboard-image-native"], "1")
check("native4", ["build/clipboard-image-native"], "4")
check("paste Bun", ["bun", "build/clipboard-paste.js"], expected=PASTE)
check("paste native1", ["build/clipboard-paste-native"], "1", PASTE)
check("paste native4", ["build/clipboard-paste-native"], "4", PASTE)
check("commands native1", ["build/clipboard-command-native"], "1", COMMANDS)
check("commands native4", ["build/clipboard-command-native"], "4", COMMANDS)
