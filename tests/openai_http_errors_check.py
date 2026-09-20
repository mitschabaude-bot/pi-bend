"""Typed native HTTP cancellation through independent wrapper combinations."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--worktree', type=Path, default=ROOT)
parser.add_argument('--no-build', action='store_true')
args = parser.parse_args()
WORK = args.worktree.resolve()
compiler = ROOT / 'build/bend-profiles/dns-transport-teles/bend2'
prefix = WORK / 'build/openai-http-errors'
source = 'tests/openai-http-errors.bend'
if not args.no_build:
    for backend in ['c', 'js']:
        with Path(f'{prefix}-{backend}-build.log').open('w') as log:
            subprocess.run(['python3', str(ROOT / 'scripts/run-rss-guarded.py'), '--limit-gib', '8',
                            '--stats', f'{prefix}-{backend}-build.json', '--', str(compiler / 'main.ts'), source,
                            '-o', f'{prefix}.{backend}'], cwd=WORK, check=True, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(['clang', '-std=c11', '-fbracket-depth=2048', '-O1', f'{prefix}.c', '-lpthread', '-lm', '-o', str(prefix)], check=True)

arguments, expected = [], []
for leaf, reader, exchange, progress in itertools.product(range(12), range(3), range(3), range(5)):
    # Only default/supplied socket aborts and upload abort without cleanup are
    # lone aborts. Additional causes at any enclosing layer retain failure.
    leaf_abort = leaf in (0, 1, 3)
    native_abort = leaf_abort and (exchange == 1 or (exchange == 0 and reader in (0, 1)))
    arguments.append(','.join(map(str, (leaf, reader, exchange, progress))))
    expected.append('abort' if native_abort and progress in (0, 1) else 'failure')
runs = []
for label, command in [
    ('native-1', [str(prefix), '--threads', '1']),
    ('native-4', [str(prefix), '--threads', '4']),
    ('bun', [str(Path.home() / '.bun/bin/bun'), str(prefix) + '.js']),
]:
    result = subprocess.run(command + arguments, cwd=WORK, text=True, capture_output=True, check=True, timeout=60)
    assert result.stdout.splitlines() == expected and not result.stderr, (label, result.stdout, result.stderr)
    runs.append({'backend': label, 'cases': len(arguments), 'passed': True})
    print(label, len(arguments), 'typed cancellation classifications PASS', flush=True)

pending, visited = [WORK / source], set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    pending += [path.parent / name for name in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE)]
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=WORK, text=True).strip()
new_files = {'packages/runtime/src/http-abort-classification.bend', 'packages/runtime/src/http-response-progress.bend',
             'packages/runtime/src/http-response-metadata.bend', 'packages/ai/src/api/openai-http-errors.bend', source}
for path in visited:
    name = str(path.relative_to(WORK))
    reference = (ROOT / name).read_bytes() if name in new_files else subprocess.check_output(['git', 'show', base + ':' + name], cwd=WORK)
    assert reference == path.read_bytes(), name
record = {
    'scope': '540 finite native typed-error combinations per backend. Checks default/supplied cancellation, upload cleanup, read/release/disposal combinations, missing head/completion, and ordinary errors whose text resembles cancellation. Pure generic classification has separate laws.',
    'validated_checkout': {'base_commit': base, 'new_files': sorted(new_files), 'pending_form_drafts_included': False},
    'runs': runs,
    'source_sha256': {str(path.relative_to(WORK)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(visited)},
    'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'compiler_sha256': {name: hashlib.sha256((compiler / name).read_bytes()).hexdigest() for name in ['main.ts','bend.ts','comp.ts','base.bend']},
    'builds': {backend: json.loads(Path(f'{prefix}-{backend}-build.json').read_text()) for backend in ['c','js']},
}
(ROOT / 'build/openai-http-errors-results.json').write_text(json.dumps(record, indent=2) + '\n')
