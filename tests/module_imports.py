"""Regression for Bend's shared-file namespace resolution across sibling packages."""
import os
from pathlib import Path
from bend_toolchain import BEND
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
(ROOT / 'build').mkdir(exist_ok=True)
BEND = BEND
with tempfile.TemporaryDirectory(prefix='module-imports-', dir=ROOT / 'build') as directory:
    tree = Path(directory)
    for subdir in ('a/test', 'a/src', 'b/src'):
        (tree / subdir).mkdir(parents=True)
    (tree / 'a/src/shared.bend').write_text('import Base\ndef value() -> U32: 41\n')
    (tree / 'b/src/dependent.bend').write_text('import Base\nimport ../../a/src/shared.bend as Shared\ndef value() -> U32: (Shared.value() + 1 : U32)\n')
    imports = ['import ../src/shared.bend as Shared', 'import ../../b/src/dependent.bend as Dependent']
    for order in (imports, list(reversed(imports))):
        entry = tree / 'a/test/main.bend'
        entry.write_text('import Base\n' + '\n'.join(order) + '''
def main() -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_eq((Shared.value() + Dependent.value() : U32), 83), IO.print("PASS shared namespace"), IO.die(Unit, 1, "module aliases resolved incorrectly"))
''')
        output = tree / 'main'
        subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', str(entry), str(output)], cwd=ROOT, check=True)
        subprocess.run([str(output), '--threads', '1'], check=True, timeout=20)
    # Reusing a completed import must not accidentally accept an active cycle.
    entry.write_text('import Base\nimport ../src/cycle.bend as Cycle\ndef main() -> IO(Unit): IO.print("unreachable")\n')
    (tree / 'a/src/cycle.bend').write_text('import Base\nimport ../test/main.bend as Main\ndef value() -> U32: 0\n')
    result = subprocess.run([BEND, str(entry), '-o', str(tree / 'cycle.c')], text=True, capture_output=True, timeout=30)
    assert result.returncode != 0 and 'an import cycle' in result.stdout + result.stderr, result
print('PASS cross-package diamonds in both load orders and cycle rejection')
