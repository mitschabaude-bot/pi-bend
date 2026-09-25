#!/usr/bin/env python3
"""Inventory pinned pi source files and their Bend counterparts.

File presence is deliberately separate from behavioral coverage. Review states
live in docs/source-coverage-reviews.json, never in filename heuristics.
"""

import argparse
import hashlib
import json
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ("ai", "agent", "tui", "coding-agent")
REVIEWS = ROOT / "docs/source-coverage-reviews.json"
OUTPUT = ROOT / "docs/source-coverage.json"
VALID_STATES = {"unreviewed", "partial", "ported", "missing", "excluded"}


def source_files(upstream):
    for package in PACKAGES:
        source_root = upstream / "packages" / package / "src"
        for path in sorted(source_root.rglob("*")):
            if path.is_file() and path.suffix in {".ts", ".tsx"} and not path.name.endswith(".d.ts"):
                yield path


def load_reviews():
    data = json.loads(REVIEWS.read_text())
    if set(data) != {"revision", "reviews"}:
        raise ValueError("review file must contain revision and reviews")
    if not isinstance(data["reviews"], dict):
        raise ValueError("reviews must be a source-path keyed object")
    return data


def build(upstream):
    reviews = load_reviews()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, text=True).strip()
    if revision != reviews["revision"]:
        raise ValueError(f"upstream is at {revision}; reviews target {reviews['revision']}")

    entries = []
    seen = set()
    for path in source_files(upstream):
        source = path.relative_to(upstream).as_posix()
        seen.add(source)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        direct = ROOT / Path(source).with_suffix(".bend")
        review = reviews["reviews"].get(source, {})
        if set(review) - {"state", "ports", "note", "source_sha256"}:
            raise ValueError(f"unknown review keys for {source}")
        state = review.get("state", "unreviewed")
        if state not in VALID_STATES:
            raise ValueError(f"invalid state {state} for {source}")
        if state != "unreviewed" and review.get("source_sha256") != digest:
            raise ValueError(f"review of changed source {source} is stale; inspect upstream and update source_sha256")
        ports = review.get("ports", [direct.relative_to(ROOT).as_posix()] if direct.is_file() else [])
        if not isinstance(ports, list) or any(not isinstance(p, str) or not p.startswith("packages/") or not p.endswith(".bend") for p in ports):
            raise ValueError(f"invalid ports for {source}")
        for port in ports:
            if not (ROOT / port).is_file():
                raise ValueError(f"missing port {port} for {source}")
        if state == "ported" and not ports:
            raise ValueError(f"ported source has no targets: {source}")
        if state == "missing" and ports:
            raise ValueError(f"missing source has targets: {source}")
        entry = {
            "source": source,
            "sha256": digest,
            "ports": ports,
            "state": state,
        }
        if "note" in review:
            entry["note"] = review["note"]
        entries.append(entry)

    unknown = set(reviews["reviews"]) - seen
    if unknown:
        raise ValueError(f"reviews for absent upstream files: {sorted(unknown)}")
    return {"revision": revision, "scope": [f"packages/{p}/src" for p in PACKAGES], "entries": entries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated map is stale")
    parser.add_argument("--reference", type=Path, default=ROOT.parent / "pi-mono", help="upstream checkout")
    args = parser.parse_args()
    result = json.dumps(build(args.reference.resolve()), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != result:
            raise SystemExit("source-coverage.json is stale; run scripts/source_coverage.py")
    else:
        OUTPUT.write_text(result)

    data = json.loads(result)
    grouped = defaultdict(list)
    for entry in data["entries"]:
        grouped[entry["source"].split("/")[1]].append(entry)
    for package in PACKAGES:
        rows = grouped[package]
        counts = Counter(row["state"] for row in rows)
        print(f"{package}: {len(rows)} source files, {sum(bool(row['ports']) for row in rows)} mapped; " + ", ".join(f"{state}={counts[state]}" for state in sorted(counts)))


if __name__ == "__main__":
    main()
