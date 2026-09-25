#!/usr/bin/env python3
"""pi's packages/tui/test/markdown.test.ts against the Bend Markdown
component: tests/markdown_test_reference.ts runs upstream's test file with a
recording Markdown (all 81 tests must pass there) and records every
Markdown each test creates, its calls and rendered lines;
tests/markdown-test.bend replays them. A test passes when every render of
every Markdown it created has identical lines and its transform calls
match. The assertions upstream makes through the TUI and a virtual terminal
are about those same lines as painted; the painting is the TUI's contract.

Usage: python3 tests/markdown_test_check.py [bend-toolchain main.ts] [pi-mono]
"""
import collections, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
PI = sys.argv[2] if len(sys.argv) > 2 else '/home/agent/code/pi-mono'
OUT = ROOT / 'build/markdown-test'
OUT.mkdir(parents=True, exist_ok=True)
print(subprocess.run(['bun', str(ROOT / 'tests/markdown_test_reference.ts'), str(OUT), PI], check=True, cwd=ROOT, capture_output=True, text=True).stdout.strip())
subprocess.run(['bun', BEND, 'tests/markdown-test.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
got = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, check=True, cwd=ROOT).stdout.splitlines()
expected = (OUT / 'expected.jsonl').read_text().splitlines()
labels = [json.loads(line) for line in (OUT / 'labels.jsonl').read_text().splitlines()]
tests = json.loads((OUT / 'tests.json').read_text())
failed = collections.OrderedDict()
for i, want in enumerate(expected):
    have = got[i] if i < len(got) else 'missing'
    if have != want:
        failed.setdefault(labels[i], (i, have, want))
for name, (i, have, want) in list(failed.items())[:8]:
    print(f'FAIL {name}\n  bend {have[:400]}\n  pi   {want[:400]}')
covered = set(labels)
for name in tests:
    if name not in covered:
        print(f'no Markdown rendered: {name}')
print(f'{len(tests) - len(failed)}/{len(tests)} markdown.test.ts tests: every Markdown render matches ({len(expected)} instances)')
sys.exit(1 if failed or covered != set(tests) else 0)
