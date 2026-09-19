"""Create an isolated, additive timer-primitive experiment; never install it."""
from pathlib import Path
import shutil
import sys
root=Path(__file__).resolve().parents[1]
baseline=Path.home()/'.bend/current/bend2'
candidate=Path(sys.argv[1]).resolve()
assert not candidate.exists(), 'Use a fresh candidate directory'
shutil.copytree(baseline,candidate)
addition=root/'patches/experimental/timer'
with (candidate/'base.bend').open('a') as out:out.write((addition/'base.bend').read_text())
for name in ['timer.c','timer.js']:shutil.copyfile(addition/name,candidate/'effs'/name)
print(candidate)
