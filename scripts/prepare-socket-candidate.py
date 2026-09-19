"""Prepare isolated TCP bytes + socket control effects; never modify installation."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
candidate = Path(sys.argv[1]).resolve()
assert not candidate.exists(), 'Use a fresh candidate directory'
shutil.copytree(Path.home() / '.bend/current/bend2', candidate)
subprocess.run(['patch', '-p2', '-i', str(root / 'patches/experimental/bend-tcp-bytes.patch')], cwd=candidate, check=True)
addition = root / 'patches/experimental/socket-control'
with (candidate / 'base.bend').open('a') as out:
    out.write((addition / 'base.bend').read_text())
for name in ['socket_duplicate.c', 'socket_duplicate.js', 'tcp_shutdown.c', 'tcp_shutdown.js', 'socket_is_connection_reset.c', 'socket_is_connection_reset.js']:
    shutil.copyfile(addition / name, candidate / 'effs' / name)
print(candidate)
