"""Append the isolated numeric IPv6 connect primitive; never install it."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('--base', type=Path, default=Path.home()/'.bend/current/bend2')
args = parser.parse_args()
assert not args.destination.exists(), 'Use a fresh candidate directory'
shutil.copytree(args.base, args.destination)
source = ROOT/'patches/experimental/ipv6-connect'
with (args.destination/'base.bend').open('a') as out:
    out.write((source/'base.bend').read_text())
for name in ['tcp_connect_ipv6.c', 'tcp_connect_ipv6.js']:
    shutil.copyfile(source/name, args.destination/'effs'/name)
for path in args.base.rglob('*'):
    if path.is_file() and path.relative_to(args.base).as_posix() != 'base.bend':
        assert path.read_bytes() == (args.destination/path.relative_to(args.base)).read_bytes(), path
assert (args.destination/'base.bend').read_bytes() == (args.base/'base.bend').read_bytes() + (source/'base.bend').read_bytes()
print(json.dumps({'base':str(args.base.resolve()),'candidate':str(args.destination.resolve()),'comp_sha256':hashlib.sha256((args.base/'comp.ts').read_bytes()).hexdigest()}))
