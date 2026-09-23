"""Exercise native --export from an unrelated working directory."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
SOURCE = ROOT / "tests/fixtures/export-input.jsonl"

with tempfile.TemporaryDirectory(prefix="pi-export-cli-") as directory:
    cwd = Path(directory)
    for threads, output in ((1, None), (4, "named.html")):
        args = [str(BINARY), "--threads", str(threads), "--", "--export", str(SOURCE)]
        if output:
            args.append(output)
        process = subprocess.run(args, cwd=cwd, capture_output=True, timeout=30)
        expected = cwd / (output or "pi-session-export-input.html")
        assert process.returncode == 0, (threads, process.stderr)
        assert process.stdout.decode().strip() == f"Exported to: {expected}"
        html = expected.read_text()
        payload = re.search(r'<script id="session-data" type="application/json">([A-Za-z0-9+/=]+)</script>', html)
        assert payload, threads
        data = json.loads(base64.b64decode(payload.group(1)))
        assert data["header"]["id"] == "export-1"
        assert [entry["id"] for entry in data["entries"]] == ["u1", "a1", "r1"]
        assert "<script>alert(1)</script> & é" not in html
        print(f"native{threads}: --export wrote a safe standalone viewer from another cwd")

    missing = subprocess.run([str(BINARY), "--threads", "1", "--", "--export", str(cwd / "missing.jsonl")], cwd=cwd, capture_output=True, timeout=30)
    assert missing.returncode == 1 and b"Error:" in missing.stderr
    print("native1: missing export source reports an error")
