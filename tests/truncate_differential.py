"""Compare native Bend results with the pinned upstream TypeScript implementation."""
import json
import random
import subprocess
import tempfile

rng = random.Random(813)
texts = ["", "\n", "\n\n", "a\n", "a\nb\n", "é😊", "\r\n", "x" * 51300, "line\n" * 2100]
cases = [{"text": text, "lines": lines, "bytes": size} for text in texts for lines in [0, 1, 2, 2000] for size in [0, 1, 4, 51200]]
for _ in range(120):
    text = "".join(rng.choice(["a", "é", "😃", "\n", "\r", "中", "\t"]) for _ in range(rng.randrange(80)))
    cases.append({"text": text, "lines": rng.randrange(12), "bytes": rng.randrange(60)})
with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as file:
    json.dump(cases, file)
    file.flush()
    expected = json.loads(subprocess.check_output(["bun", "tests/truncate_reference.ts", file.name], text=True))
    actual = json.loads(subprocess.check_output(["build/test-truncate-runner", file.name], text=True, timeout=120))
assert len(actual) == len(expected)
for index, (got, want) in enumerate(zip(actual, expected)):
    assert got == want, (index, cases[index], got, want)
print(f"truncate: {len(cases)} native/upstream differential cases passed")
