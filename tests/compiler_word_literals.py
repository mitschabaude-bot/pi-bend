"""Compare compiler representations on literal and runtime-supplied words."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--candidate', type=Path, required=True)
a = p.parse_args()
out = ROOT / 'build/compiler-word-literals'
out.mkdir(exist_ok=True)
source = ROOT / 'tests/compiler-word-literals.bend'
records = {}
for label, compiler in [('baseline', a.baseline.resolve()), ('candidate', a.candidate.resolve())]:
    prefix = out / label
    with prefix.with_suffix('.log').open('w') as log:
        subprocess.run(['bun', str(compiler), str(source), '-o', str(prefix.with_suffix('.c')), '-o', str(prefix.with_suffix('.js'))], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    records[label] = {'compiler': {name: hashlib.sha256((compiler.parent/name).read_bytes()).hexdigest() for name in ['main.ts', 'bend.ts', 'comp.ts', 'base.bend']}, 'programs': {ext: hashlib.sha256(prefix.with_suffix(ext).read_bytes()).hexdigest() for ext in ['.c', '.js']}}
assert records['baseline']['programs'] == records['candidate']['programs'], records
prefix = out / 'candidate'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang', '-std=c11', '-fbracket-depth=2048', '-O1', str(prefix.with_suffix('.c')), '-lpthread', '-lm', '-o', str(prefix)], check=True)
numbers = [0, 1, 2, 255, 65535, 2147483648, 4294967295]
integers = lambda values: [f'{n}:{n}:{int(n != 0)}' for n in values]
floats = [0.0, -0.0, 1.0, 0.1, 1.17549435e-38, 1.40129846e-45, 3.40282347e38]
expected = integers([0, 1, 2147483648, 4294967295]) + [str(struct.unpack('<I', struct.pack('<f', n))[0]) for n in floats] + integers(numbers)
for backend, command in [('native-1', [str(prefix), '--threads', '1']), ('native-4', [str(prefix), '--threads', '4']), ('bun', ['bun', str(prefix.with_suffix('.js'))])]:
    run = subprocess.run(command + list(map(str, numbers)), cwd=ROOT, capture_output=True, text=True, check=True)
    assert not run.stderr and run.stdout.splitlines() == expected, (backend, run.stdout, run.stderr, expected)
    print(backend, 'literal, generic, reconstructed and runtime words PASS')
records.update(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), expected=expected, backends=['native-1', 'native-4', 'bun'])
(out/'results.json').write_text(json.dumps(records, indent=2)+'\n')
