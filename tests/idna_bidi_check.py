"""RFC 5893 six-condition rule; property lookup/whole IDNA tested separately."""
from itertools import product
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CLASSES = 'L R AL EN AN ES CS ET ON BN NSM B S WS LRE LRO RLE RLO PDF LRI RLI FSI PDI'.split()
ALPHABET = ''.join(chr(97 + i) for i in range(len(CLASSES)))

# Declarative reference: allowed class sets, first class, last non-NSM class,
# and digit coexistence, rather than the production incremental state machine.
def reference(text):
    classes = [CLASSES[ord(c) - 97] for c in text]
    present = set(classes)
    rtl = bool(present & {'R', 'AL', 'AN'})
    valid = False
    ending = [c for c in classes if c != 'NSM']
    if classes and classes[0] in {'R', 'AL'}:
        valid = (present <= {'R', 'AL', 'AN', 'EN', 'ES', 'CS', 'ET', 'ON', 'BN', 'NSM'}
                 and ending[-1] in {'R', 'AL', 'EN', 'AN'}
                 and not {'EN', 'AN'} <= present)
    elif classes and classes[0] == 'L':
        valid = (present <= {'L', 'EN', 'ES', 'CS', 'ET', 'ON', 'BN', 'NSM'}
                 and ending[-1] in {'L', 'EN'})
    return str(int(rtl)) + str(int(valid))

texts = [''.join(row) for n in range(4) for row in product(ALPHABET, repeat=n)]
# All four-character transitions using every allowed class and one rejected class.
texts += [''.join(row) for row in product(ALPHABET[:12], repeat=4)]
rng = random.Random(5893)
texts += [''.join(rng.choice(ALPHABET) for _ in range(rng.randrange(4, 128))) for _ in range(500)]
# Long NSM suffixes, interrupted suffixes, late digit mixing and RTL after failure.
for count in [1024, 16384, 65536]:
    texts += [prefix + 'k' * count + suffix for prefix, suffix in
              [('a', ''), ('b', ''), ('bf', ''), ('bd', 'e'), ('l', 'b'), ('af', 'a')]]
expected = [reference(text) for text in texts]
if '--no-build' not in sys.argv:
    subprocess.run(['sh', 'scripts/build-pure.sh', 'packages/runtime/test/idna-bidi.bend', 'build/idna-bidi'], cwd=ROOT, check=True)
subprocess.run([str(Path(BEND)), 'packages/runtime/test/idna-bidi.bend', '-o', 'build/idna-bidi.js'], cwd=ROOT, check=True)
for label, command in [('native 1', ['build/idna-bidi', '--threads', '1']), ('native 4', ['build/idna-bidi', '--threads', '4']), ('Bun', [str(Path.home()/'.bun/bin/bun'), 'build/idna-bidi.js'])]:
    # Each large input is below Linux's per-argument bound; the batch is <2 MiB.
    for start in range(0, len(texts), 128):
        result = subprocess.run([*command, *texts[start:start+128]], cwd=ROOT, text=True, capture_output=True, timeout=60)
        assert result.returncode == 0, (label, start, result.stderr)
        for offset, (got, want) in enumerate(zip(result.stdout.splitlines(), expected[start:start+128], strict=True)):
            assert got == want, (label, start + offset, texts[start+offset], got, want)
    print(f'{label}: {len(texts)} Bidi rule comparisons PASS', flush=True)
