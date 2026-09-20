"""Prepare additive binary datagram reception without changing the installation."""
import argparse
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination',type=Path)
parser.add_argument('--base',type=Path,default=Path.home()/'.bend/current/bend2')
args=parser.parse_args()
assert not args.destination.exists(),'Use a fresh candidate directory'
shutil.copytree(args.base,args.destination)
addition=ROOT/'patches/experimental/udp-bytes'
with (args.destination/'base.bend').open('a') as output:output.write((addition/'base.bend').read_text())
for source in [*addition.glob('*.c'), *addition.glob('*.js')]:shutil.copyfile(source,args.destination/'effs'/source.name)
for path in args.base.rglob('*'):
    if path.is_file() and path.relative_to(args.base).as_posix()!='base.bend':
        assert path.read_bytes()==(args.destination/path.relative_to(args.base)).read_bytes(),path
assert (args.destination/'base.bend').read_bytes()==(args.base/'base.bend').read_bytes()+(addition/'base.bend').read_bytes()
print(args.destination.resolve())
