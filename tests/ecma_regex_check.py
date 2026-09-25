#!/usr/bin/env python3
"""runtime/ecma-regex.bend against JavaScript RegExp on real workloads.

Records every RegExp exec call highlight.js 10.7.3 (pi's highlighter) makes
while highlighting snippets in its 20 eager languages (tests/ecma_regex_record.mjs,
a test-only oracle using the installed pi package), replays each call in Bend
(tests/ecma-regex-replay.bend) and compares match and capture indices.

Usage: python3 tests/ecma_regex_check.py [bend-toolchain main.ts]
"""
import os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
OUT = ROOT / 'build/ecma-regex'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['bun', str(ROOT / 'tests/ecma_regex_record.mjs'), str(OUT)], check=True)
subprocess.run(['bun', BEND, 'tests/ecma-regex-replay.bend', '-o', str(OUT / 'replay.js')], check=True, cwd=ROOT)
cases = (OUT / 'cases.txt').read_text().splitlines()
expected = (OUT / 'expected.txt').read_text().splitlines()
(OUT / 'all.txt').write_text('\n'.join(cases) + '\n')
got = []
# The JavaScript lane's stack does not unwind across many heavy cases in one
# process, so cases replay in small batches.
for start in range(0, len(cases), 20):
    (OUT / 'cases.txt').write_text('\n'.join(cases[start:start + 20]) + '\n')
    result = subprocess.run(['bun', str(OUT / 'replay.js')], capture_output=True, text=True, cwd=ROOT)
    lines = result.stdout.splitlines()
    if len(lines) != len(cases[start:start + 20]):
        lines = []
        for case in cases[start:start + 20]:
            (OUT / 'cases.txt').write_text(case + '\n')
            one = subprocess.run(['bun', str(OUT / 'replay.js')], capture_output=True, text=True, cwd=ROOT)
            lines.append((one.stdout.strip() or one.stderr.strip()).splitlines()[0] if (one.stdout.strip() or one.stderr.strip()) else '')
    got.extend(lines)
bad = [(i, g, e) for i, (g, e) in enumerate(zip(got, expected)) if g != e]
for i, g, e in bad[:10]:
    print(f'case {i + 1}: bend {g[:120]!r} js {e[:120]!r}')
print(f'{len(cases) - len(bad)}/{len(cases)} exec calls match JavaScript')
sys.exit(1 if bad or len(got) != len(expected) else 0)
