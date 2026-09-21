"""Bounded conversion-checking probe; never executes the recursive IO program."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--timeout', type=float, default=5)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
compiler = args.compiler.resolve()
source = (ROOT / 'tests/compiler-io-equality.bend').read_text()
cases = {
    'recursive-wrapper': source,
    'recursive-direct': source.replace('wrapped(Unit{}) ==', 'repeat(Unit{}) =='),
    'finite-wrapper': source.replace('    repeat(Unit{})', '    return Unit{}'),
    'constant-distinct-arguments': '''import Base
def constant(unused: Nat) -> Nat: 0n
law constant_equal:
  for x: Nat
  for y: Nat
  {constant(x) == constant(y) : Nat}
def constant_equal(x, y): {==}
''',
    'constant-unused-finite-argument': (ROOT / 'tests/compiler-unused-argument.bend').read_text(),
    'constant-unused-recursive-argument': '''import Base
@unsafe def loop(unused: Unit) -> Nat: loop(Unit{})
def constant(unused: Nat) -> Nat: 0n
law discarded_argument:
  {constant(loop(Unit{})) == constant(0n) : Nat}
def discarded_argument(): {==}
''',
}
records = []
with tempfile.TemporaryDirectory(prefix='bend-io-equality-') as directory:
    for name, text in cases.items():
        path = Path(directory) / (name + '.bend')
        path.write_text(text)
        start = time.monotonic()
        try:
            result = subprocess.run(['bun', str(compiler), str(path)], capture_output=True, text=True, timeout=args.timeout)
            output = result.stdout + result.stderr
            status = result.returncode
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b'').decode() + (error.stderr or b'').decode()
            status = 'timeout'
        checked = 'All terms check' in output
        if name in ['finite-wrapper', 'constant-distinct-arguments']:
            assert status == 0 and checked, (name, status, output)
        records.append(dict(case=name, source=text, status=status, checked=checked, seconds=time.monotonic()-start, output=output))
        print(name, status, 'checked' if checked else 'not checked', flush=True)
record = dict(scope=__doc__, timeout_seconds=args.timeout, compiler=str(compiler), sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), ROOT / 'tests/compiler-io-equality.bend', ROOT / 'tests/compiler-unused-argument.bend']}, compiler_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in compiler.parent.iterdir() if p.suffix in ['.ts', '.bend']}, runs=records)
args.output.write_text(json.dumps(record, indent=2) + '\n')
