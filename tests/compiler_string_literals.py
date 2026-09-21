"""Compare literal representation through generic storage and captured functions."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--candidate', type=Path, required=True)
args = p.parse_args()
out = ROOT / 'build/compiler-string-literals'
out.mkdir(exist_ok=True)
source = ROOT / 'tests/compiler-string-literals.bend'
texts = ['', 'plain', '\0\n\t\r\\"', 'éλ中😀', '\U0001f600\0\U0010ffff', 'a😀b']
expected = [ ''.join(f'{ord(c)}:' for c in text) + 'end' for text in texts ]
records = {}
for variant, compiler in [('baseline', args.baseline.resolve()), ('candidate', args.candidate.resolve())]:
    prefix = out / variant
    subprocess.run(['bun', str(compiler), str(source), '-o', str(prefix.with_suffix('.c')),
                    '-o', str(prefix.with_suffix('.js'))], cwd=ROOT, check=True)
    records[variant] = {ext: hashlib.sha256(prefix.with_suffix(ext).read_bytes()).hexdigest()
                        for ext in ['.c', '.js']}
    subprocess.run(['clang', '-O1', '-std=c11', '-fbracket-depth=2048', str(prefix.with_suffix('.c')),
                    '-o', str(prefix), '-lpthread', '-lm'], check=True)
    for command in [[str(prefix), '--threads', '1'], [str(prefix), '--threads', '4'],
                    ['bun', str(prefix.with_suffix('.js'))]]:
        run = subprocess.run(command, capture_output=True, text=True, check=True, timeout=60)
        assert not run.stderr and run.stdout.splitlines() == expected, (command, run.stdout, run.stderr)
    print(variant, 'string literals: native 1/4 and Bun PASS', flush=True)
assert records['baseline'] == records['candidate'], records
records.update(expected=expected, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
(out / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
