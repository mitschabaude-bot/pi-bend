import json
import pathlib
import subprocess
import tempfile

RUNNER = pathlib.Path("build/test-tools").resolve()


def call(cwd, name, **args):
    p = subprocess.run([str(RUNNER), name, json.dumps(args)], cwd=cwd, text=True, capture_output=True, timeout=20)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout)


with tempfile.TemporaryDirectory(prefix="pi-bend-tools-") as directory:
    root = pathlib.Path(directory)
    assert call(root, "write", path="nested/test.txt", content="hello α\nsecond\nthird")["error"] is False
    assert (root / "nested/test.txt").read_text() == "hello α\nsecond\nthird"
    assert call(root, "read", path="nested/test.txt")["text"] == "hello α\nsecond\nthird"
    assert call(root, "read", path="nested/test.txt", offset=2, limit=1)["text"].startswith("second\n\n[")
    assert call(root, "read", path="nested/test.txt", offset=10)["error"] is True
    assert call(root, "edit", path="nested/test.txt", oldText="hello α", newText="hello β")["error"] is False
    assert (root / "nested/test.txt").read_text().startswith("hello β")
    before = (root / "nested/test.txt").read_bytes()
    assert call(root, "edit", path="nested/test.txt", oldText="missing", newText="oops")["error"] is True
    assert (root / "nested/test.txt").read_bytes() == before
    (root / "duplicate").write_text("same same")
    assert call(root, "edit", path="duplicate", oldText="same", newText="different")["error"] is True
    assert (root / "duplicate").read_text() == "same same"
    assert call(root, "bash", command="printf hi; printf err >&2; exit 7") == {"text": "hierr\n\nCommand exited with code 7", "error": True}
    assert call(root, "bash", command="sleep 5", timeout=1)["error"] is True
    assert call(root, "read", path="absent")["error"] is True
    assert call(root, "write", path="untouched")["error"] is True
    assert not (root / "untouched").exists()
print("tools: all tests passed")
