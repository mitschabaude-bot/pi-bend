"""Check native concatenation values, retained aliases and concurrent readers."""
import argparse
import itertools
import random
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
args = parser.parse_args()
atoms = ("", "a", "é", "e\u0301", "日本語", "🙂", "𐀀", "\n\t", '"', "\\")
pairs = list(itertools.product(atoms, repeat=2))
rng = random.Random(471)
pairs += [("".join(rng.choices(atoms, k=rng.randrange(40))),
           "".join(rng.choices(atoms, k=rng.randrange(40)))) for _ in range(200)]
expected = "".join("\n".join(("True", str(not (a + b)), a + b,
                               (a + b)[::-1], (a + b)[:3], (a + b)[3:], "True")) + "\n"
                   for a, b in pairs)
for threads in ("1", "4"):
    command = [str(args.binary.resolve()), "--threads", threads]
    result = subprocess.run(command + [v for pair in pairs for v in pair],
                            capture_output=True, text=True, check=True, timeout=30)
    assert result.stdout == expected, (threads, result.stdout[:300], result.stderr)
    assert not result.stderr, result.stderr
    for _ in range(3):
        result = subprocess.run(command + ["parallel"], capture_output=True,
                                text=True, check=True, timeout=30)
        assert result.stdout == "1728000\n", (threads, result.stdout, result.stderr)
        assert not result.stderr, result.stderr
    print(f"native {threads}: {len(pairs)} concatenation cases and 32 concurrent readers pass")
