#!/usr/bin/env python3
"""Check hand-reviewed upstream source coverage against the pinned trees."""
import sys; sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "tests"))
from upstream_pin import UPSTREAM

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REVIEWS = ROOT / "docs/source-coverage-reviews.json"
VALID_STATES = {"partial", "ported", "missing", "excluded"}


def check(upstream):
    data = json.loads(REVIEWS.read_text())
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, text=True).strip()
    if revision != data["revision"]:
        raise ValueError(f"upstream is at {revision}; reviews target {data['revision']}")
    for source, review in data["reviews"].items():
        path = upstream / source
        if not path.is_file():
            raise ValueError(f"reviewed source no longer exists: {source}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if review["source_sha256"] != digest:
            raise ValueError(f"review of changed source {source} is stale")
        if review["state"] not in VALID_STATES:
            raise ValueError(f"invalid state for {source}")
        ports = review.get("ports")
        if ports is None:
            direct = ROOT / Path(source).with_suffix(".bend")
            ports = [direct.relative_to(ROOT).as_posix()] if direct.is_file() else []
        if review["state"] == "ported" and not ports:
            raise ValueError(f"ported source has no Bend target: {source}")
        if review["state"] == "missing" and ports:
            raise ValueError(f"missing source has Bend targets: {source}")
        port_hashes = review.get("port_sha256", {})
        if set(port_hashes) != set(ports):
            raise ValueError(f"Bend target hashes do not match targets for {source}")
        for port in ports:
            if not port.startswith("packages/") or not port.endswith(".bend") or not (ROOT / port).is_file():
                raise ValueError(f"invalid Bend target {port} for {source}")
            if port_hashes[port] != hashlib.sha256((ROOT / port).read_bytes()).hexdigest():
                raise ValueError(f"review of changed Bend target {port} is stale")
    print(f"Upstream source reviews: {len(data['reviews'])} checked at {revision[:9]}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=UPSTREAM)
    args = parser.parse_args()
    check(args.reference.resolve())
