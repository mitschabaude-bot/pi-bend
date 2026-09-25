#!/usr/bin/env python3
"""Pinned named assertions plus exact native prompt/section/patch comparisons."""
from upstream_pin import UPSTREAM
import argparse
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--upstream', default=str(UPSTREAM))
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command
if command[:1] == ['--']:
    command = command[1:]
assert command, 'provide compiled fixture command after --'
root = pathlib.Path(__file__).resolve().parent.parent
reference = json.loads(subprocess.check_output(['bun', 'tests/system_prompt_reference.ts', str(pathlib.Path(args.upstream).resolve())], cwd=root, text=True))
large = next(case for case in reference['records'] if case['input']['op'] == 'large')
records = [case for case in reference['records'] if case['input']['op'] != 'large']
# Intentional strict section-name boundary: JS regex $ accepts a final newline.
records.append({'name': 'reject trailing newline in section name', 'input': {'op':'sections','options': {'cwd':'/', 'sections': {'name\n':'x'}}}, 'expected': {'error':'Invalid system prompt section name: name\n'}})
for start in range(0, len(records), 20):
    batch = records[start:start+20]
    result = subprocess.run(command + [json.dumps(case['input'], ensure_ascii=False) for case in batch], text=True, capture_output=True, check=True, timeout=120)
    lines = result.stdout.splitlines()
    assert len(lines) == len(batch), (start, len(lines), result.stderr)
    for case, line in zip(batch, lines):
        actual = json.loads(line)
        assert actual == case['expected'], (case['name'], repr(actual)[:500], repr(case['expected'])[:500])
large_result = subprocess.run(command + ['--large-context'], text=True, capture_output=True, check=True, timeout=120)
assert large_result.stdout == large['expected'] + '\n', 'large project-context rendering mismatch'
large_json = subprocess.run(command + [json.dumps(large['input'])], text=True, capture_output=True, check=True, timeout=120)
assert json.loads(large_json.stdout) == large['expected'], 'large project-context JSON mismatch'
print(f"{len(reference['names'])} pinned named assertions; {len(records)+1} exact comparisons including 150KB context: passed")
