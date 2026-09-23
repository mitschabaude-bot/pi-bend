"""Compare pi's pinned terminal palette and ANSI colors with native Bend."""
import random
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
rng = random.Random(91341)
channels = [0, 8, 13, 14, 47, 48, 94, 95, 115, 116, 135, 155, 156, 175, 195, 196, 215, 235, 236, 238, 255]
colors = {(r,g,b) for r in channels for g in channels for b in channels if max(r,g,b)-min(r,g,b) < 10}
colors.update((v,v,v) for v in range(256))
colors.update((rng.randrange(256),rng.randrange(256),rng.randrange(256)) for _ in range(3000))
values = [f'#{r:02x}{g:02x}{b:02x}' for r,g,b in sorted(colors)]
def run(command):
    return subprocess.run(command+values,cwd=root,check=True,capture_output=True).stdout
expected = run(['bun','tests/theme-color-reference.ts'])
for backend,command in [
    ('bun',['bun','build/theme-color.js']),
    ('native-1',['build/theme-color','--threads','1']),
    ('native-4',['build/theme-color','--threads','4']),
]:
    actual = run(command)
    assert actual == expected, (backend,next((i for i,(a,b) in enumerate(zip(actual.splitlines(),expected.splitlines())) if a!=b),None))
    print(f'{backend}: {len(values)} palette/ANSI colors match pinned pi')
