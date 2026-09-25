#!/usr/bin/env python3
"""utils/changelog.bend against upstream utils/changelog.ts on the real CHANGELOG.md.

Runs tests/changelog.bend (ported unit cases) and compares every parsed entry
with normalized links, byte for byte, with upstream's parseChangelog +
normalizeChangelogLinks on ../pi-mono/packages/coding-agent/CHANGELOG.md.

  python3 tests/changelog_check.py
"""
from upstream_pin import UPSTREAM
import subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BEND = str(ROOT / "build/bend-native-toolchain/bend2/main.ts")
UPSTREAM = UPSTREAM / 'packages/coding-agent'
unit = subprocess.run(["bun", BEND, "tests/changelog.bend"], cwd=ROOT, capture_output=True, text=True, timeout=900)
print(unit.stdout, end="")
assert unit.returncode == 0 and "FAIL" not in unit.stdout, unit.stdout + unit.stderr
script = (f'import {{ normalizeChangelogLinks, parseChangelog }} from "{UPSTREAM}/src/utils/changelog.ts";'
          f'const e = parseChangelog("{UPSTREAM}/CHANGELOG.md");'
          'process.stdout.write(e.map((x) => normalizeChangelogLinks(x.content, x)).join("\\n\\n") + "\\n");')
expected = subprocess.run(["bun", "-e", script], cwd=ROOT, capture_output=True, text=True, check=True).stdout
actual = subprocess.run(["bun", BEND, "tests/changelog-all.bend"], cwd=ROOT, capture_output=True, text=True, timeout=900).stdout
assert actual == expected, "normalized changelog differs from upstream"
print(f"changelog: {expected.count(chr(10))} lines of normalized entries identical to upstream")
