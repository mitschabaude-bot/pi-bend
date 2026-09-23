"""Exercise native --export from an unrelated working directory."""
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
SOURCE = ROOT / "tests/fixtures/export-input.jsonl"


def session_payload(path):
    html = path.read_text()
    payload = re.search(r'<script id="session-data" type="application/json">([A-Za-z0-9+/=]+)</script>', html)
    assert payload
    assert "<script>alert(1)</script> & é" not in html
    return json.loads(base64.b64decode(payload.group(1)))


with tempfile.TemporaryDirectory(prefix="pi-export-cli-") as directory:
    cwd = Path(directory)
    source = cwd / "export-input.jsonl"
    shutil.copyfile(SOURCE, source)
    for threads, output in ((1, None), (4, "named.html")):
        args = [str(BINARY), "--threads", str(threads), "--", "--export", str(source)]
        if output:
            args.append(output)
        process = subprocess.run(args, cwd=cwd, capture_output=True, timeout=30)
        expected = cwd / (output or "pi-session-export-input.html")
        assert process.returncode == 0, (threads, process.stderr)
        assert process.stdout.decode().strip() == f"Exported to: {expected}"
        data = session_payload(expected)
        assert data["header"]["id"] == "export-1"
        assert [entry["id"] for entry in data["entries"]] == ["u1", "a1", "r1"]
        print(f"native{threads}: --export wrote a safe standalone viewer from another cwd")

    missing = subprocess.run([str(BINARY), "--threads", "1", "--", "--export", str(cwd / "missing.jsonl")], cwd=cwd, capture_output=True, timeout=30)
    assert missing.returncode == 1 and b"Error:" in missing.stderr
    print("native1: missing export source reports an error")

    rpc = subprocess.run(
        [str(BINARY), "--threads", "1", "--", "--mode", "rpc", "--session", str(source)],
        input=b'{"id":"export","type":"export_html","outputPath":"rpc.html"}\n',
        cwd=cwd, capture_output=True, timeout=30,
    )
    assert rpc.returncode == 0 and not rpc.stderr, rpc.stderr
    responses = (json.loads(line) for line in rpc.stdout.splitlines())
    response = next(item for item in responses if item.get("id") == "export")
    assert response == {"id": "export", "type": "response", "command": "export_html", "success": True, "data": {"path": str(cwd / "rpc.html")}}
    assert session_payload(cwd / "rpc.html")["header"]["id"] == "export-1"
    print("native1: RPC export_html wrote the selected persisted session")
