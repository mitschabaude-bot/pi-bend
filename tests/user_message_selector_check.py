"""Compare fork-list selection and full component rendering with pinned pi."""
import difflib
import json
import os
from pathlib import Path
import subprocess
from upstream_pin import UPSTREAM

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_USER_SELECTOR", ROOT / "build/user-message-selector")).resolve()
actions = ["up", "up", "down", "left", "x", "enter", "escape"]
cases = [dict(width=100, initial="", actions=actions, texts=[])]
for count in (1, 8, 10, 11, 23):
    texts = [f"Message {i}\n café 日本語\tend " for i in range(count)]
    for width, initial in ((24, ""), (100, "0"), (7, "missing")):
        cases.append(dict(width=width, initial=initial, actions=actions + ["down"] * (count + 1), texts=texts))
cases.append(dict(width=24, initial="1", actions=actions, texts=["  spaced\ntext  ", "\x1b[31mred 日本語\x1b[0m", "a" * 150]))
expected = json.loads(subprocess.check_output(["bun", "tests/user_message_selector_reference.mts"], input=json.dumps(cases), text=True, cwd=ROOT))
for threads in (1, 4):
    for index, (case, wanted) in enumerate(zip(cases, expected, strict=True)):
        result = subprocess.run([str(BINARY), "--threads", str(threads), "--", str(ROOT), str(case["width"]), case["initial"], ",".join(case["actions"]), *case["texts"]], cwd=ROOT, capture_output=True, text=True, check=True, timeout=10)
        assert not result.stderr, result.stderr
        actual = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(actual) == len(wanted), (threads, index, len(actual), len(wanted))
        for step, (got, want) in enumerate(zip(actual, wanted, strict=True)):
            difference = "\n".join(difflib.unified_diff(json.dumps(want, indent=2).splitlines(), json.dumps(got, indent=2).splitlines(), fromfile="pi", tofile="bend"))
            assert got == want, (threads, index, step, case["width"], difference[:2000])
    print(f"native{threads}: {len(cases)} fork-list cases match pi selection, actions and ANSI rendering")
