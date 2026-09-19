"""BEND-012: typed do bindings must shadow globals identically after import."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(Path.home() / '.bend/bin/bend'))
(ROOT / 'build').mkdir(exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--expect-bug', action='store_true')
args = parser.parse_args()
expected = ['PASS typed do binding'] * 5

with tempfile.TemporaryDirectory(prefix='typed-do-', dir=ROOT / 'build') as directory:
    folder = Path(directory)
    library = folder / 'library.bend'
    shutil.copyfile(ROOT / 'tests/typed-do-shadow.bend', library)
    entry = folder / 'entry.bend'
    entry.write_text('import Base\nimport ./library.bend as Library\ndef main() -> IO(Unit): Library.main()\n')
    if args.expect_bug:
        direct = subprocess.check_output([BEND, str(library)], cwd=ROOT, text=True, timeout=60)
        assert direct.splitlines() == expected, direct
        imported = subprocess.run([BEND, str(entry), '-o', str(folder / 'failed.c')], cwd=ROOT, text=True, capture_output=True, timeout=60)
        assert imported.returncode != 0 and "observed : ':'" in imported.stdout + imported.stderr, imported
        print('REPRODUCED standalone success and imported typed-do binding failure')
    else:
        for source in [library, entry]:
            output = source.with_suffix('')
            subprocess.run(['sh', 'scripts/build-pure.sh', str(source), str(output)], cwd=ROOT, check=True)
            for threads in ['1', '4']:
                actual = subprocess.check_output([str(output), '--threads', threads], text=True, timeout=30)
                assert actual.splitlines() == expected, actual
            js = source.with_suffix('.js')
            subprocess.run([BEND, str(source), '-o', str(js)], cwd=ROOT, check=True)
            actual = subprocess.check_output([shutil.which('bun') or str(Path.home() / '.bun/bin/bun'), str(js)], text=True, timeout=30)
            assert actual.splitlines() == expected, actual
        entry.write_text('import Base\nimport ./library.bend as Library\ndef main() -> IO(Unit):\n  do IO<Unit>:\n    Library.answer : U32 <- IO.pure(U32, 1)\n    IO.print("invalid qualified binder")\n')
        invalid = subprocess.run([BEND, str(entry), '-o', str(folder / 'invalid.c')], text=True, capture_output=True, timeout=30)
        assert invalid.returncode != 0, invalid
        print('PASS typed do shadowing in standalone/imported native one/four-thread and JS builds; qualified names remain invalid binders')
