"""Validate native String.eq semantics and retained-root ownership."""
import argparse
import itertools
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
args = parser.parse_args()
symbols = ("", "a", "b", "\x1b[31m", "日本", "😀", "é", "\t", "\r\n")
values = list(symbols) + [a + b for a, b in itertools.product(symbols[1:5], repeat=2)]
values += ["x" * 2000, "x" * 1999 + "y"]
pairs = list(itertools.product(values, repeat=2))
expected = "1:2:2:1:1:1\n0:2:2:1:0:0\n" + "".join(
    f"{int(a == b)}:{len(a)}:{len(b)}:1:{int(a == b)}:{int(a == b)}\n" for a, b in pairs)
for threads in ("1", "4"):
    result = subprocess.run(
        [str(args.binary.resolve()), "--threads", threads, "nul", *[v for pair in pairs for v in pair]],
        capture_output=True, text=True, check=True, timeout=30)
    assert result.stdout == expected, (threads, result.stdout[:300], result.stderr)
    assert not result.stderr, result.stderr
    print(f"native {threads}: {len(pairs) + 2} equality/storage/retained-alias cases pass")
