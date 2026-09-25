#!/usr/bin/env python3
"""pi's terminal LaTeX rendering against pi-mono (upstream latex.ts and the
LaTeX tokens of the TUI Markdown component).

tests/latex_reference.ts (a test-only oracle importing pi-mono's sources)
writes the cases, upstream's results and a label per case: every assertion
of latex.test.ts and the LaTeX tests of markdown.test.ts under their test
names, then a differential corpus. tests/latex.bend must print the same.

Usage: python3 tests/latex_check.py [bend-toolchain main.ts]
"""
import collections, json, os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
OUT = ROOT / 'build/latex'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['bun', str(ROOT / 'tests/latex_reference.ts'), str(OUT)], check=True, cwd=ROOT)
subprocess.run(['bun', BEND, 'tests/latex.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
got = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, cwd=ROOT).stdout.splitlines()
cases = (OUT / 'cases.jsonl').read_text().splitlines()
expected = (OUT / 'expected.jsonl').read_text().splitlines()
labels = [json.loads(line) for line in (OUT / 'labels.jsonl').read_text().splitlines()]
differ = [i for i, e in enumerate(expected) if i >= len(got) or got[i] != e]
# Cases labelled "known divergence" document an accepted difference (see
# tests/latex_reference.ts); they are reported, not failed on.
known = [i for i in differ if labels[i].startswith('known divergence')]
bad = [i for i in differ if not labels[i].startswith('known divergence')]
for i in bad[:10]:
    print(f'case {i + 1} ({labels[i]}): {cases[i][:160]}\n  bend {got[i][:240] if i < len(got) else "<missing>"}\n  pi   {expected[i][:240]}')
group = lambda label: label.split(':')[0] if ':' in label else label
totals = collections.Counter(group(label) for label in labels)
failed = collections.Counter(group(labels[i]) for i in differ)
for name, total in totals.items():
    print(f'{total - failed[name]}/{total} {name}')
compared = len(cases) - sum(1 for label in labels if label.startswith('known divergence'))
print(f'{compared - len(bad)}/{compared} LaTeX cases match pi; {len(known)} known divergences differ')
sys.exit(1 if bad else 0)
