"""Check real rename/delete reloads and lazy cache invalidation against pi."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
def seed(root):
    (root / "sessions").mkdir()
    (root / "project").mkdir()
    (root / "home").mkdir()
    for index, (id, name, project) in enumerate([("alpha", "Alpha", "project"), ("beta", "Beta", "project"), ("other", "Other", "other-project")]):
        records = [dict(type="session", version=3, id=id, timestamp="2025-01-01T00:00:00Z", cwd=str(root / project)), dict(type="session_info", id=id + "-name", parentId=None, timestamp="2025-01-01T00:00:01Z", name=name)]
        path = root / "sessions" / (id + ".jsonl")
        path.write_text("".join(json.dumps(record) + "\n" for record in records))
        os.utime(path, (1736000000 - index * 1000,) * 2)

def run(command):
    with tempfile.TemporaryDirectory(prefix="pi-resume-mutation-") as place:
        root = Path(place)
        seed(root)
        env = dict(os.environ, HOME=str(root / "home"), PI_CODING_AGENT_DIR=str(root / "home/.pi/agent"))
        result = subprocess.run(command + [str(root), str(ROOT)], cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (command, result.returncode, result.stderr)
        assert not result.stderr, result.stderr
        return [json.loads(line.replace(str(root), "<root>")) for line in result.stdout.splitlines()]

expected = run(["bun", "tests/resume_mutation_reference.mts"])
lanes = [("bun", ["bun", "build/resume-mutation.js"])] if os.environ.get("PI_BEND_RESUME_BUN") else [(f"native{n}", ["build/resume-mutation", "--threads", str(n), "--"]) for n in (1, 4)]
for lane, command in lanes:
    actual = run(command)
    assert actual == expected, (lane, actual, expected)
    print(f"{lane}: rename/delete caches and lazy reloads match pi across {len(actual)} stages")
