#!/usr/bin/env python3
"""pi's Markdown component (packages/tui/src/components/markdown.bend) against
upstream's (tests/markdown_render_reference.ts, a test-only oracle importing
pi-mono's markdown.ts and its marked): hand-written and cross-line cases,
the Markdown of marked's spec tests and seeded random documents, in plain,
marker, ANSI and highlighting themes, with default text styles, padding,
options and widths. tests/markdown-render.bend prints the Bend lines.

marked's spec inputs come from its v18.0.11 source archive (downloaded by
tests/marked_lexer_check.py into build/marked-source).

Usage: python3 tests/markdown_render_check.py [bend-toolchain main.ts] [pi-mono]
"""
import collections, json, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
PI = sys.argv[2] if len(sys.argv) > 2 else '/home/agent/code/pi-mono'
OUT = ROOT / 'build/markdown-render'
SOURCE = ROOT / 'build/marked-source'
OUT.mkdir(parents=True, exist_ok=True)
if not (SOURCE / 'test/specs').exists():
    subprocess.run([sys.executable, str(ROOT / 'tests/marked_lexer_check.py'), BEND, PI], check=True, cwd=ROOT)
subprocess.run(['bun', str(ROOT / 'tests/markdown_render_reference.ts'), str(OUT), str(SOURCE), PI], check=True, cwd=ROOT)
subprocess.run(['bun', BEND, 'tests/markdown-render.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
cases = (OUT / 'cases.jsonl').read_text().splitlines()
expected = (OUT / 'expected.jsonl').read_text().splitlines()
labels = [json.loads(line) for line in (OUT / 'labels.jsonl').read_text().splitlines()]
(OUT / 'all.jsonl').write_text('\n'.join(cases) + '\n')
got = []
BATCH = 50
for start in range(0, len(cases), BATCH):
    (OUT / 'cases.jsonl').write_text('\n'.join(cases[start:start + BATCH]) + '\n')
    result = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, cwd=ROOT)
    lines = result.stdout.splitlines()
    if len(lines) != len(cases[start:start + BATCH]):
        lines += ['<failed: ' + result.stderr.strip()[-200:] + '>'] * (len(cases[start:start + BATCH]) - len(lines))
    got += lines
(OUT / 'cases.jsonl').write_text('\n'.join(cases) + '\n')
(OUT / 'got.jsonl').write_text('\n'.join(got) + '\n')
bad = [i for i in range(len(cases)) if got[i] != expected[i]]
for i in bad[:10]:
    case = json.loads(cases[i])
    print(f'case {i + 1} ({labels[i]}, width {case["width"]}, {case["theme"]}/{case["style"]}): {case["text"][:100]!r}')
    for g, w in zip(json.loads(got[i]) if got[i].startswith('[') else [got[i]], json.loads(expected[i])):
        if g != w:
            print(f'  bend {g!r}\n  pi   {w!r}')
            break
    else:
        print(f'  bend {got[i][:300]}\n  pi   {expected[i][:300]}')
group = lambda label: label.split(' ')[0]
totals = collections.Counter(group(label) for label in labels)
failed = collections.Counter(group(labels[i]) for i in bad)
for name, total in totals.items():
    print(f'{total - failed[name]}/{total} {name}')
print(f'{len(cases) - len(bad)}/{len(cases)} Markdown renders match pi')
sys.exit(1 if bad else 0)
