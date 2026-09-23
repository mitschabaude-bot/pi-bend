#!/usr/bin/env python3
"""Compare native branch collection with pinned pi v0.87.1."""
import hashlib
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", COMMON.parent.parent / "pi-mono"))
SOURCE = UPSTREAM / "packages/coding-agent/src/core/compaction/branch-summarization.ts"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "0279195d2cddfe99d4e42a1327d18c7f55ff15a8807d2c5d6cd465b2ab163011"

REFERENCE = r'''
import { collectEntriesForBranchSummary, prepareBranchEntries } from "./packages/coding-agent/src/core/compaction/branch-summarization.ts";
const entries = ["u1", "u2", "u3"].map((id, i) => ({ type: "message", id, parentId: i ? "u1" : null, timestamp: "2025-01-01", message: { role: "user", content: ["first", "second", "third"][i], timestamp: 1 } }));
const byId = Object.fromEntries(entries.map(e => [e.id, e]));
const session = { getBranch(id) { return id === "u2" ? [byId.u1, byId.u2] : [byId.u1, byId.u3]; }, getEntry(id) { return byId[id]; } };
const collected = collectEntriesForBranchSummary(session, "u3", "u2");
const prepared = prepareBranchEntries(collected.entries, 100);
console.log(`${collected.commonAncestorId}|${collected.entries.map(e => e.id).join(",")}|${prepared.messages.length}`);
'''

expected = subprocess.check_output(["bun", "-e", REFERENCE], cwd=UPSTREAM, text=True).strip()
for label, command in (
    ("Bun", ["bun", str(ROOT / "build/branch-summarization.js")]),
    ("native1", [str(ROOT / "build/branch-summarization-native"), "--threads", "1"]),
    ("native4", [str(ROOT / "build/branch-summarization-native"), "--threads", "4"]),
):
    actual = subprocess.check_output(command, cwd=ROOT, text=True).strip()
    assert actual == expected, (label, actual, expected)
    print(f"{label}: {actual}")
