"""Check indexed constructor fields and string fallback reconstruction on both backends."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--candidate', type=Path, required=True)
args = p.parse_args()
out = ROOT / 'build/compiler-field-cache'
out.mkdir(exist_ok=True)
records = {}
for fixture in ['compiler-string-pattern-return', 'compiler-word-field-cache', 'compiler-nat-match-table']:
    source = ROOT / 'tests' / (fixture + '.bend')
    if fixture == 'compiler-string-pattern-return':
        names = re.findall(r'case "([^"]+)":', source.read_text())
        inputs = list(dict.fromkeys(names + ['', 'unknown', 'é', '😀']
            + [word[:i] for word in names for i in range(len(word))]
            + [word + 'x' for word in names]
            + [word[:i] + 'X' + word[i + 1:] for word in names for i in range(len(word))]))
        expected = [str(names.index(word) + 1) if word in names else word for word in inputs]
    elif fixture == 'compiler-word-field-cache':
        inputs = ['0', '1']
        expected = ['' if n == 0 else bit + '0' * (n - 1)
            for bit in inputs for n in [0, 1, 31, 32, 33]]
    else:
        inputs = []
        expected = ['91', '7', '44', '5']
    artifacts = {}
    for variant, compiler in [('baseline', args.baseline.resolve()), ('candidate', args.candidate.resolve())]:
        folder = out / fixture / variant
        folder.mkdir(parents=True, exist_ok=True)
        prefix = folder / 'program'
        with (folder / 'compiler.log').open('w') as log:
            subprocess.run(['bun', str(compiler), str(source), '-o', str(prefix.with_suffix('.c')),
                            '-o', str(prefix.with_suffix('.js'))], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        artifacts[variant] = {ext: hashlib.sha256(prefix.with_suffix(ext).read_bytes()).hexdigest() for ext in ['.c', '.js']}
        subprocess.run(['clang', '-O1', '-std=c11', '-fbracket-depth=2048', str(prefix.with_suffix('.c')),
                        '-o', str(prefix), '-lpthread', '-lm'], check=True)
        for command in [[str(prefix), '--threads', '1'], [str(prefix), '--threads', '4'], ['bun', str(prefix.with_suffix('.js'))]]:
            run = subprocess.run(command + inputs, capture_output=True, text=True, check=True, timeout=60)
            assert not run.stderr and run.stdout.splitlines() == expected, (fixture, variant, command, run.stdout, run.stderr, expected)
        print(f'{fixture} {variant}: {len(expected)} cases per backend PASS', flush=True)
    assert artifacts['baseline'] == artifacts['candidate'], (fixture, artifacts)
    records[fixture] = dict(artifacts=artifacts, cases_per_backend=len(expected), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
records['compilers'] = {variant: {name: hashlib.sha256((compiler.resolve().parent / name).read_bytes()).hexdigest()
    for name in ['bend.ts', 'comp.ts', 'main.ts', 'base.bend']}
    for variant, compiler in [('baseline', args.baseline), ('candidate', args.candidate)]}
(out / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
