"""Prepare a minimal weak-key compiler cache experiment; never install it."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import sys

ROOT=Path(__file__).resolve().parents[1]
BASELINE=Path.home()/'.bend/current/bend2'

def transform(source):
    replacements=[
        ('const TELES: Map<HTerm, ReturnType<typeof Bend.tele_unbind>> = new Map();',
         'let TELES: WeakMap<HTerm, ReturnType<typeof Bend.tele_unbind>> = new WeakMap();'),
        ('function memo<K, V>(m: Map<K, V>, k: K, f: () => V): V {',
         'function memo<K, V>(m: { get(k: K): V | undefined; set(k: K, v: V): void }, k: K, f: () => V): V {'),
        ('  [TELES, SRCS, NODES, CYCLES, FLATS, SIGS, BRWS].forEach((m) => m.clear());',
         '  TELES = new WeakMap();\n  [SRCS, NODES, CYCLES, FLATS, SIGS, BRWS].forEach((m) => m.clear());'),
    ]
    for old,new in replacements:
        assert source.count(old)==1,old
        source=source.replace(old,new)
    return source

def verify(candidate):
    assert (candidate/'comp.ts').read_text()==transform((BASELINE/'comp.ts').read_text())
    for path in BASELINE.rglob('*'):
        if path.is_file() and path.relative_to(BASELINE).as_posix()!='comp.ts':
            assert path.read_bytes()==(candidate/path.relative_to(BASELINE)).read_bytes(),path

if __name__=='__main__':
    candidate=Path(sys.argv[1]).resolve()
    assert not candidate.exists(),'Use a fresh candidate directory'
    shutil.copytree(BASELINE,candidate)
    original=(BASELINE/'comp.ts').read_text()
    changed=transform(original)
    (candidate/'comp.ts').write_text(changed)
    verify(candidate)
    patch=ROOT/'patches/experimental/bend-weak-teles.patch'
    patch.write_text(''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),fromfile='a/bend2/comp.ts',tofile='b/bend2/comp.ts')))
    print(json.dumps({'candidate':str(candidate),'patch':str(patch),'baseline_sha256':hashlib.sha256(original.encode()).hexdigest(),'candidate_sha256':hashlib.sha256(changed.encode()).hexdigest()}))
