"""Compare deferred resume loading and full frames against pinned pi."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
def session(id, modified):
    return dict(id=id, path=f"/tmp/{id}.jsonl", modified=modified, name=id)
def key(value):
    return dict(kind="key", key=value)
def progress(scope, items, loaded=1, total=3):
    return dict(kind="progress", scope=scope, items=items, loaded=loaded, total=total)
def complete(scope, items):
    return dict(kind="complete", scope=scope, items=items)
a, b, c = session("Alpha", 10000), session("Beta", 20000), session("Charlie", 30000)
cases = []
for width in (30, 100):
    for touch in ([], [key("up")], [key("down"), key("up")], [key("Beta")]):
        cases.append(dict(width=width, actions=[progress("current", [b, a]), *touch, progress("current", [c, b, a], 2), complete("current", [c, b, a])]))
    cases.append(dict(width=width, actions=[progress("current", [a]), key("scope"), progress("all", [b]), key("scope"), complete("all", [c, b]), complete("current", [a]), key("scope"), key("scope"), key("scope")]))
    cases.append(dict(width=width, actions=[progress("current", [a, b]), key("scope"), progress("all", [b, a]), key("down"), progress("all", [c, b, a], 2), complete("all", [c, b, a]), key("path")]))
    cases.append(dict(width=width, actions=[key("scope"), complete("current", []), progress("all", [], 0, 0), complete("all", []), key("scope")]))
expected = json.loads(subprocess.check_output(["bun", "tests/resume_loading_reference.mts"], input=json.dumps(cases), text=True, cwd=ROOT))
lanes = [("bun", ["bun", "build/resume-loading.js"])] if os.environ.get("PI_BEND_RESUME_BUN") else [(f"native{n}", ["build/resume-loading", "--threads", str(n), "--"]) for n in (1, 4)]
for lane, command in lanes:
    result = subprocess.run(command + [str(ROOT), json.dumps(cases)], cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (lane, result.returncode, result.stderr)
    assert not result.stderr, result.stderr
    actual = [json.loads(line) for line in result.stdout.splitlines()]
    wanted = [(i, j, value) for i, steps in enumerate(expected) for j, value in enumerate(steps)]
    assert len(actual) == len(wanted), (lane, len(actual), len(wanted))
    differences = [(i, j, [field for field in got if got[field] != want[field]], got, want) for got, (i, j, want) in zip(actual, wanted, strict=True) if got != want]
    assert not differences, (lane, len(differences), differences[:2])
    print(f"{lane}: {len(cases)} delayed loading cases match selection, scope, progress and ANSI frames")
