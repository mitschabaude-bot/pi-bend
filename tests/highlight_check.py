#!/usr/bin/env python3
"""runtime/src/highlight.bend against highlight.js 10.7.3.

tests/highlight_reference.mjs (a test-only oracle using the highlight.js pi
installs) writes cases -- hand-written snippets, a generic snippet in every
language, and 50-line windows of public source files on this machine -- with
highlight.js's HTML value for each. tests/highlight-replay.bend highlights the
same cases with every language registered; the HTML must be identical. Also
checks that all generated grammars load (tests/highlight-grammars.bend).

Usage: python3 tests/highlight_check.py [--no-corpus] [bend-toolchain main.ts]
"""
import json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
args = [a for a in sys.argv[1:] if not a.startswith('--')]
BEND = args[0] if args else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
OUT = ROOT / 'build/highlight'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['bun', str(ROOT / 'tests/highlight_reference.mjs'), str(OUT)] + (['--no-corpus'] if '--no-corpus' in sys.argv else []), check=True, cwd=ROOT)
for name in ['highlight-grammars', 'highlight-replay']:
    subprocess.run(['bun', BEND, f'tests/{name}.bend', '-o', str(OUT / f'{name}.js')], check=True, cwd=ROOT)
grammars = subprocess.run(['bun', str(OUT / 'highlight-grammars.js')], capture_output=True, text=True, cwd=ROOT)
print(grammars.stdout.strip())
got = subprocess.run(['bun', str(OUT / 'highlight-replay.js')], capture_output=True, text=True, cwd=ROOT).stdout.splitlines()
cases = (OUT / 'cases.jsonl').read_text().splitlines()
expected = (OUT / 'expected.jsonl').read_text().splitlines()
bad = [i for i, (g, e) in enumerate(zip(got, expected)) if g != e]
for i in bad[:10]:
    case = json.loads(cases[i])
    g, e = json.loads(got[i]) or '', json.loads(expected[i]) or ''
    at = next((k for k in range(min(len(g), len(e))) if g[k] != e[k]), min(len(g), len(e)))
    print(f"case {i + 1} ({case['language']}, {case.get('source', 'snippet')}): at {at}\n  bend {g[max(0, at - 80):at + 80]!r}\n  hljs {e[max(0, at - 80):at + 80]!r}")
print(f'{len(cases) - len(bad) - (len(cases) - len(got))}/{len(cases)} highlight results match highlight.js')
sys.exit(1 if bad or len(got) != len(expected) or grammars.returncode != 0 else 0)
