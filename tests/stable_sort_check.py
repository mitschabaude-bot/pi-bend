"""Stable ordering of immutable records, including long equal-key runs."""
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
rows = [(count, seed, modulus) for count in [0, 1, 2, 3, 7, 16, 63, 128, 1024, 16384, 65536] for seed in [0, 1, 4294967295] for modulus in [1, 2, 257, 4294967295]]
expected = []
for count, seed, modulus in rows:
    values = []
    for index in range(count):
        seed = (seed * 1664525 + 1013904223) & 0xffffffff
        values.append((seed % modulus, index))
    result = sorted(values, key=lambda item: item[0])
    hash_value = 2166136261
    for key, index in result:
        hash_value = ((hash_value * 16777619) & 0xffffffff) ^ key
        hash_value = ((hash_value * 16777619) & 0xffffffff) ^ index
    expected.append(f'{count};{hash_value}')
if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh','packages/runtime/test/stable-sort.bend','build/stable-sort'],cwd=ROOT,check=True)
subprocess.run([str(Path(BEND)),'packages/runtime/test/stable-sort.bend','-o','build/stable-sort.js'],cwd=ROOT,check=True)
for label, command in [('native 1',['build/stable-sort','--threads','1']),('native 4',['build/stable-sort','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/stable-sort.js'])]:
    for start in range(0,len(rows),8):
        args = [';'.join(map(str,row)) for row in rows[start:start+8]]
        result=subprocess.run([*command,*args],cwd=ROOT,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(label,start,result.stderr)
        assert result.stdout.splitlines()==expected[start:start+8],(label,start,result.stdout,expected[start:start+8])
    print(f'{label}: {len(rows)} stable-sort record cases PASS',flush=True)
