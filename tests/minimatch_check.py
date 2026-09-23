#!/usr/bin/env python3
"""Differential checks of runtime/minimatch.bend against pi's pinned minimatch@10.2.6.

Usage: python3 tests/minimatch_check.py [--fixture FILE] -- <compiled tests/minimatch.bend command>
The fixture is regenerated with `bun tests/minimatch_oracle.ts` unless given.
"""
import argparse
import json
import subprocess
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--fixture')
parser.add_argument('--batch', type=int, default=400)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
assert command, 'supply the compiled fixture command'

root = Path(__file__).resolve().parent.parent
if args.fixture:
    fixture = json.loads(Path(args.fixture).read_text())
else:
    fixture = json.loads(subprocess.check_output(['bun', str(root / 'tests/minimatch_oracle.ts')], text=True))


def run(requests):
    """Answers for `mode<US>fields` requests; results may span lines, so a
    batch is split on the known count of answers."""
    answers = []
    for start in range(0, len(requests), args.batch):
        group = requests[start:start + args.batch]
        result = subprocess.run(command + group, capture_output=True, text=True)
        lines = result.stdout.split('\n')
        if result.returncode == 0 and len(lines) == len(group) + 1 and lines[-1] == '':
            answers.extend(lines[:-1])
            continue
        # Crashed batch, or answers containing line breaks: one process each.
        for request in group:
            single = subprocess.run(command + [request], capture_output=True, text=True)
            answers.append(single.stdout[:-1] if single.returncode == 0 else 'crash: ' + single.stderr.strip()[:80])
    return answers


cases = fixture['match']
answers = run(['m\x1f' + path + '\x1f' + pattern for path, pattern, _ in cases])
failures = [(case, got) for case, got in zip(cases, answers) if case[2] != got]
for (path, pattern, expected), got in failures[:30]:
    print(f'path={path[:80]!r} pattern={pattern[:80]!r} expected={expected} got={got[:80]}')
assert not failures, f'{len(failures)} / {len(cases)} match mismatches'
counts = Counter(expected for _, _, expected in cases)
print(f"{len(cases)} minimatch cases passed ({counts['true']} true, {counts['false']} false, {counts['throw']} throw)")

def one_line(text):
    return text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r')


braces = [(pattern, one_line(expected)) for pattern, expected in fixture['brace']]
answers = run(['b\x1f' + pattern for pattern, _ in braces])
failures = [(case, got) for case, got in zip(braces, answers) if case[1] != got]
for (pattern, expected), got in failures[:30]:
    print(f'pattern={pattern!r} expected={expected[:120]!r} got={got[:120]!r}')
assert not failures, f'{len(failures)} / {len(braces)} braceExpand mismatches'
print(f'{len(braces)} braceExpand cases passed')
