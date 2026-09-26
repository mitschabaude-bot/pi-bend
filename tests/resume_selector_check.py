"""Compare resume ordering, controls and complete frames with pinned pi."""
import difflib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def session(id, parent=None, modified=0, name=None, **fields):
    return dict(id=id, path=f"/tmp/{id}.jsonl", parentSessionPath=f"/tmp/{parent}.jsonl" if parent else None, modified=modified, name=name, **fields)

cases = []
forests = [
    [session("parent-one", modified=20000, name="Parent one"), session("parent-two", modified=10000, name="Parent two"), session("child-two", "parent-two", 30000, "Child two")],
    [session("root", modified=20000, name="Root"), session("left", "root", 10000, "Left"), session("right", "root", 30000, "Right"), session("grandchild", "left", 50000, "Grandchild")],
    [session("first", modified=10000, firstMessage="  first\nquestion  "), session("second", modified=30000, name="Named"), session("third", modified=20000, name="   ")],
    [session(str(i), parent=str(i // 3) if i > 0 else None, modified=i * 1000, name=f"Session {i}" if i % 2 else None) for i in range(17)],
    [session("orphan", "missing", 10000, "Orphan"), session("root", modified=10000, name="Root")],
    [],
]
for forest in forests:
    for width in (30, 100):
        cases.append(dict(width=width, current=forest, all=list(reversed(forest)), actions=["down", "up", "page-down", "page-up", "path", "path", "down", "sort", "sort", "sort", "named", "named", "scope", "scope"]))
for active in (None, "/tmp/a.jsonl"):
    cases.append(dict(width=100, current=[session("a", modified=20000, name="Active"), session("b", modified=10000, name="Other")], active=active, actions=(["delete", "down", "path"] if active else ["delete", "escape", "down", "delete", "down", "path", "escape", "a", "delete-alias", "delete", "escape"])))
cases.append(dict(width=100, current=[session("a", name="First"), session("b", name="Second")], actions=["delete-alias", "escape"]))
# Active-session protection must recognize different filesystem aliases.
with tempfile.TemporaryDirectory(prefix="pi-resume-paths-") as directory:
    root = Path(directory)
    (root / "real").mkdir()
    (root / "real/session.jsonl").write_text("session\n")
    (root / "a").symlink_to(root / "real", target_is_directory=True)
    (root / "b").symlink_to(root / "real", target_is_directory=True)
    cases.append(dict(width=100, current=[dict(session("alias", name="Active alias"), path=str(root / "b/session.jsonl"))], active=str(root / "a/session.jsonl"), actions=["delete"]))
    expected = json.loads(subprocess.check_output(["bun", "tests/resume_selector_reference.mts"], input=json.dumps(cases), text=True, cwd=ROOT))
    lanes = [("bun", ["bun", os.environ.get("PI_BEND_RESUME_BUN_BINARY", "build/resume-selector.js")])] if os.environ.get("PI_BEND_RESUME_BUN") else [(f"native{n}", [os.environ.get("PI_BEND_RESUME_SELECTOR", "build/resume-selector"), "--threads", str(n), "--"]) for n in (1, 4)]
    for lane, command in lanes:
        result = subprocess.run(command + [str(ROOT), json.dumps(cases)], cwd=ROOT, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (lane, result.returncode, result.stderr)
        assert not result.stderr, result.stderr
        actual = [json.loads(line) for line in result.stdout.splitlines()]
        wanted = [(i, j, value) for i, steps in enumerate(expected) for j, value in enumerate(steps)]
        assert len(actual) == len(wanted), (lane, len(actual), len(wanted))
        differences = []
        for got, (case, step, want) in zip(actual, wanted, strict=True):
            difference = "\n".join(difflib.unified_diff(json.dumps(want, indent=2).splitlines(), json.dumps(got, indent=2).splitlines(), fromfile="pi", tofile="bend"))
            if got != want:
                differences.append((case, step, [key for key in got if got[key] != want[key]], difference))
        assert not differences, (lane, len(differences), [(case, step, fields) for case, step, fields, _ in differences[:20]], differences[0][3][:4000])
        print(f"{lane}: {len(cases)} resume cases match ordering, selection, controls and full ANSI frames")
