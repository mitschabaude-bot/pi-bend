#!/usr/bin/env python3
"""Record upstream suites without treating unported tests as passing coverage."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--reference", default="../pi-mono")
parser.add_argument("--update", action="store_true")
args = parser.parse_args()
root = pathlib.Path(args.reference).resolve()
revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
manifest = pathlib.Path("tests/upstream-inventory.json")
previous = json.loads(manifest.read_text()) if manifest.exists() else {"suites": []}
old = {suite["source"]: suite for suite in previous["suites"]}
paths = subprocess.check_output(["rg", "--files", "packages", "-g", "*.test.ts", "-g", "*.spec.ts", "-g", "*.test.js", "-g", "*.test.mjs"], cwd=root, text=True).splitlines()
suites = []
for path in sorted(paths):
    digest = hashlib.sha256((root / path).read_bytes()).hexdigest()
    suite = dict(old.get(path, {"source": path, "status": "pending", "ports": []}))
    if suite.get("sha256", digest) != digest:
        suite["status"] = "needs-review"
    suite["sha256"] = digest
    suites.append(suite)
current = {"revision": revision, "suites": suites}
if args.update:
    manifest.write_text(json.dumps(current, indent=2) + "\n")
elif current != previous:
    raise SystemExit("Upstream inventory differs; review changes and run with --update")
counts = {status: sum(s["status"] == status for s in suites) for status in sorted({s["status"] for s in suites})}
print(f"Upstream {revision[:9]}: {len(suites)} suites; {counts}")
if not args.update:
    subprocess.check_call([sys.executable, "scripts/source_coverage.py", "--check", "--reference", str(root)])
