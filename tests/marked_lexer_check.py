#!/usr/bin/env python3
"""The marked lexer port (packages/runtime/src/marked/) against marked
18.0.11: marked's Lexer unit tests (their expected tokens), the Markdown of
its spec tests lexed by marked, a hand-written corpus and seeded random
documents (tests/marked_lexer_reference.mjs, a test-only oracle using
pi-mono's installed marked). tests/marked-lexer.bend prints the port's tokens.

marked's test inputs come from its v18.0.11 source archive, downloaded once
into build/ and checked against a pinned SHA-256.

Usage: python3 tests/marked_lexer_check.py [bend-toolchain main.ts] [pi-mono]
"""
import collections, hashlib, io, json, pathlib, subprocess, sys, tarfile, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
PI = sys.argv[2] if len(sys.argv) > 2 else '/home/agent/code/pi-mono'
OUT = ROOT / 'build/marked-lexer'
SOURCE = ROOT / 'build/marked-source'
ARCHIVE = 'https://codeload.github.com/markedjs/marked/tar.gz/refs/tags/v18.0.11'
DIGEST = 'e57942592ee7fcab46048fd01c51ec99e6e5363db1475f68076ce05d622389cd'
OUT.mkdir(parents=True, exist_ok=True)
if not (SOURCE / 'test/unit/Lexer.test.js').exists():
    data = urllib.request.urlopen(ARCHIVE, timeout=60).read()
    assert hashlib.sha256(data).hexdigest() == DIGEST, 'marked v18.0.11 archive changed'
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            parts = member.name.split('/', 1)
            if len(parts) == 2 and parts[1].startswith('test/') and member.isfile():
                target = SOURCE / parts[1]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
subprocess.run(['bun', str(ROOT / 'tests/marked_lexer_reference.mjs'), str(OUT), str(SOURCE), PI], check=True, cwd=ROOT)
subprocess.run(['bun', BEND, 'tests/marked-lexer.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
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
def parsed(line):
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return line
bad = [i for i in range(len(cases)) if parsed(got[i]) != json.loads(expected[i])]
unsupported = [i for i in bad if labels[i].startswith('unsupported options')]
failures = [i for i in bad if not labels[i].startswith('unsupported options')]
for i in failures[:12]:
    print(f'case {i + 1} ({labels[i]}): {json.loads(cases[i])["text"][:120]!r}\n  bend {got[i][:400]}\n  js   {expected[i][:400]}')
group = lambda label: label.split(':')[0].split(' example')[0].split(' ')[0] if not label.startswith('unsupported') else 'unsupported options'
totals = collections.Counter(group(label) for label in labels)
failed = collections.Counter(group(labels[i]) for i in bad)
for name, total in totals.items():
    print(f'{total - failed[name]}/{total} {name}')
compared = sum(1 for label in labels if not label.startswith('unsupported options'))
print(f'{compared - len(failures)}/{compared} token lists identical to marked; {len(unsupported)} of {len(cases) - compared} cases with options the port lacks differ')
sys.exit(1 if failures else 0)
