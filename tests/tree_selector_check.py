"""Compare native tree navigation, copying and ANSI frames with pinned pi."""
import difflib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_TREE_SELECTOR", ROOT / "build/tree-selector")).resolve()
ACTIONS = ["up", "down", "left", "right", "fold", "fold", "unfold", "copy", "labeled", "up", "all", "user", "cycle", "default", "Message", "backspace", "escape", " missing ", "escape", "enter"]
cases = []
for shape in ("chain", "roots", "star", "hidden", "hidden-star"):
    for count in (1, 3, 17):
        texts = [f"Message {i}\n café 日本語\tend " for i in range(count)]
        for width in (30, 100):
            cases.append(dict(shape=shape, width=width, initial=str(count - 1), actions=ACTIONS, texts=texts))
cases.append(dict(shape="hidden", width=100, initial="m2", actions=ACTIONS, texts=["first", "second", "branch"]))
cases.append(dict(shape="chain", width=400, initial="0", actions=["copy"], texts=["line\none " + "a" * 250]))
cases.append(dict(shape="star", width=7, initial="2", actions=["copy", "missing", "escape", "copy"], texts=["line\none", "  ", "a" * 250]))
expected = json.loads(subprocess.check_output(["bun", "tests/tree_selector_reference.mts"], input=json.dumps(cases), text=True, cwd=ROOT))
lanes = [("bun", ["bun", "build/tree-selector.js"]) ] if os.environ.get("PI_BEND_TREE_BUN") else [(f"native{n}", [str(BINARY), "--threads", str(n), "--"]) for n in (1, 4)]
for lane, command in lanes:
    for index, (case, wanted) in enumerate(zip(cases, expected, strict=True)):
        result = subprocess.run(command + [str(ROOT), str(case["width"]), case["initial"], ",".join(case["actions"]), case["shape"], *case["texts"]], cwd=ROOT, capture_output=True, text=True, check=True, timeout=20)
        assert not result.stderr, result.stderr
        actual = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(actual) == len(wanted), (lane, index, len(actual), len(wanted))
        for step, (got, want) in enumerate(zip(actual, wanted, strict=True)):
            difference = "\n".join(difflib.unified_diff(json.dumps(want, indent=2).splitlines(), json.dumps(got, indent=2).splitlines(), fromfile="pi", tofile="bend"))
            assert got == want, (lane, index, step, case["width"], difference[:4000])
    print(f"{lane}: {len(cases)} tree cases match pi selection, actions, full copy text and ANSI rendering")
