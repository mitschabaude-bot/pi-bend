#!/usr/bin/env python3
"""pi's syntax highlighting against pi-mono (upstream syntax-highlight.ts,
theme.ts highlightCode/getLanguageFromPath, TUI Markdown code blocks).

tests/syntax_highlight_reference.ts (a test-only oracle importing pi-mono's
sources) writes the cases and upstream's results: highlight() with a marker
theme before and after loadAllHighlightLanguages, supportsLanguage,
highlightCode with the dark theme, Markdown code blocks, getLanguageFromPath
and renderHighlightedHtml. tests/syntax-highlight.bend must print the same.

Usage: python3 tests/syntax_highlight_check.py [bend-toolchain main.ts]
"""
import json, os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
OUT = ROOT / 'build/syntax-highlight'
OUT.mkdir(parents=True, exist_ok=True)
# chalk styles (bold, italic) as in a colour terminal.
subprocess.run(['bun', str(ROOT / 'tests/syntax_highlight_reference.ts'), str(OUT)], check=True, cwd=ROOT, env={**os.environ, 'FORCE_COLOR': '3'}, stderr=subprocess.DEVNULL)
subprocess.run(['bun', BEND, 'tests/syntax-highlight.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
got = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, cwd=ROOT).stdout.splitlines()
cases = (OUT / 'cases.jsonl').read_text().splitlines()
expected = (OUT / 'expected.jsonl').read_text().splitlines()
bad = [i for i, (g, e) in enumerate(zip(got, expected)) if g != e]
for i in bad[:10]:
    print(f'case {i + 1}: {cases[i][:120]}\n  bend {got[i][:240]}\n  pi   {expected[i][:240]}')
print(f'{len(cases) - len(bad) - (len(cases) - len(got))}/{len(cases)} syntax highlight cases match pi')
sys.exit(1 if bad or len(got) != len(expected) else 0)
