"""Create an isolated, additive timer-primitive experiment; never install it."""
from pathlib import Path
import shutil
import argparse
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination',type=Path)
parser.add_argument('--base',type=Path,default=Path.home()/'.bend/current/bend2')
args=parser.parse_args()
baseline=args.base.resolve()
candidate=args.destination.resolve()
assert not candidate.exists(), 'Use a fresh candidate directory'
shutil.copytree(baseline,candidate)
addition=root/'patches/experimental/timer'
with (candidate/'base.bend').open('a') as out:out.write((addition/'base.bend').read_text())
for name in ['timer.c','timer.js']:shutil.copyfile(addition/name,candidate/'effs'/name)
for path in baseline.rglob('*'):
    if path.is_file() and path.relative_to(baseline).as_posix()!='base.bend':
        assert path.read_bytes()==(candidate/path.relative_to(baseline)).read_bytes(),path
assert (candidate/'base.bend').read_bytes()==(baseline/'base.bend').read_bytes()+(addition/'base.bend').read_bytes()
print(candidate)
