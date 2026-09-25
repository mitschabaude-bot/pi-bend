#!/usr/bin/env python3
"""packages/runtime/src/unicode-17-category.bend against JavaScript's `\\p{L}`
and `\\p{N}` (Bun's regular expressions, a test-only oracle) over every
Unicode scalar, and the generator's --check.

Usage: python3 tests/unicode_category_check.py [bend-toolchain main.ts]
"""
import pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
BEND = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')
if not pathlib.Path(BEND).exists():
    BEND = '/home/agent/code/pi-bend/build/bend-native-toolchain/bend2/main.ts'
OUT = ROOT / 'build/unicode-category'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/generate-category-unicode.py'), '--check'], check=True, cwd=ROOT)
oracle = 'const out=[];let previous=99;for(let cp=0;cp<0x110000;cp++){const s=String.fromCodePoint(cp);const v=/\\p{L}/u.test(s)?1:/\\p{N}/u.test(s)?2:0;if(v!==previous){out.push(`${cp}:${v}`);previous=v}}console.log(out.join("\\n"))'
expected = subprocess.run(['bun', '-e', oracle], capture_output=True, text=True, check=True).stdout.split()
subprocess.run(['bun', BEND, 'tests/unicode-category.bend', '-o', str(OUT / 'run.js')], check=True, cwd=ROOT)
got = subprocess.run(['bun', str(OUT / 'run.js')], capture_output=True, text=True, check=True, cwd=ROOT).stdout.split()
print(f'{len(got)} Bend runs, {len(expected)} JavaScript runs: {"identical" if got == expected else "DIFFERENT"}')
sys.exit(0 if got == expected else 1)
