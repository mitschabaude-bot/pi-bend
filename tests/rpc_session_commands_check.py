#!/usr/bin/env python3
"""Differential check of RPC session replacement against installed pi 0.87.1.

Both CLIs open the same stored session and receive the same commands one at a
time (upstream handles commands concurrently, so each waits for its
response). Session ids, file names and timestamps are normalised; extension
commands are dropped because extensions are not ported.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = [shutil.which("pi") or "pi"]
NATIVE = [os.environ.get("PI_BEND_CLI", str(ROOT / "build/pi-cli"))]

SESSION = [
    {"type": "session", "version": 3, "id": "11111111-1111-4111-8111-111111111111", "timestamp": "2026-09-01T00:00:00.000Z", "cwd": "{cwd}"},
    {"type": "message", "id": "u1", "parentId": None, "timestamp": "2026-09-01T00:00:01.000Z", "message": {"role": "user", "content": [{"type": "text", "text": "first question"}], "timestamp": 1788220801000}},
    {"type": "message", "id": "a1", "parentId": "u1", "timestamp": "2026-09-01T00:00:02.000Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "first answer"}], "api": "openai-responses", "provider": "openai", "model": "gpt-5", "usage": {"input": 10, "output": 5, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 15, "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0}}, "stopReason": "stop", "timestamp": 1788220802000}},
    {"type": "message", "id": "u2", "parentId": "a1", "timestamp": "2026-09-01T00:00:03.000Z", "message": {"role": "user", "content": [{"type": "text", "text": "second question"}], "timestamp": 1788220803000}},
    {"type": "message", "id": "a2", "parentId": "u2", "timestamp": "2026-09-01T00:00:04.000Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "second answer"}], "api": "openai-responses", "provider": "openai", "model": "gpt-5", "usage": {"input": 20, "output": 5, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 25, "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0}}, "stopReason": "stop", "timestamp": 1788220804000}},
]

def commands(session_path):
    return [
        {"id": "forks", "type": "get_fork_messages"},
        {"id": "commands", "type": "get_commands"},
        {"id": "fork", "type": "fork", "entryId": "u2"},
        {"id": "after-fork", "type": "get_state"},
        {"id": "fork-messages", "type": "get_messages"},
        {"id": "clone", "type": "clone"},
        {"id": "after-clone", "type": "get_state"},
        {"id": "clone-entries", "type": "get_entries"},
        {"id": "new", "type": "new_session"},
        {"id": "after-new", "type": "get_state"},
        {"id": "switch", "type": "switch_session", "sessionPath": session_path},
        {"id": "after-switch", "type": "get_state"},
        {"id": "switch-messages", "type": "get_messages"},
        {"id": "bad-fork", "type": "fork", "entryId": "a1"},
        {"id": "missing-switch", "type": "switch_session"},
        {"id": "missing-fork", "type": "fork"},
    ]

def drive(executable, extra, threads=None):
    with tempfile.TemporaryDirectory(prefix="pi-rpc-sessions-") as temp:
        root = Path(temp)
        home = root / "home"; (home / ".pi/agent").mkdir(parents=True)
        cwd = root / "project"; cwd.mkdir()
        session = cwd / "session.jsonl"
        session.write_text("".join(json.dumps(entry).replace("{cwd}", str(cwd)) + "\n" for entry in SESSION))
        env = {"PATH": os.environ["PATH"], "HOME": str(home), "PI_CODING_AGENT_DIR": str(home / ".pi/agent"),
               "OPENAI_API_KEY": "sk-test", "PI_OFFLINE": "1"}
        if threads:
            env["BEND_THREADS"] = threads
        process = subprocess.Popen(executable + extra + ["--mode", "rpc", "--session", str(session), "--provider", "openai", "--model", "gpt-5"],
                                   cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        responses = []
        try:
            for command in commands(str(session)):
                process.stdin.write(json.dumps(command) + "\n"); process.stdin.flush()
                while True:
                    line = process.stdout.readline()
                    assert line, (executable, command, process.stderr.read()[-2000:])
                    record = json.loads(line)
                    if record.get("type") == "response":
                        assert record.get("id") == command["id"], (record, command)
                        responses.append(record)
                        break
        finally:
            process.stdin.close()
            process.wait(timeout=30)
        return normalise(responses, str(root))

MALFORMED = {"missing-switch", "missing-fork"}
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
ENTRY = re.compile(r"^[0-9a-f]{8}$")
STAMPED = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_")

def normalise(value, root):
    names = {}
    entries = {}
    def text(s):
        if ENTRY.match(s):
            return entries.setdefault(s, f"<entry{len(entries)}>")
        s = s.replace(root, "<root>")
        s = STAMPED.sub("<stamp>_", s)
        return UUID.sub(lambda m: names.setdefault(m.group(0), f"<id{len(names)}>") if m.group(0) != "11111111-1111-4111-8111-111111111111" else "<original>", s)
    def walk(v, key=None):
        if isinstance(v, dict):
            if key == "data" and "commands" in v:
                v = {**v, "commands": [c for c in v["commands"] if c.get("source") != "extension"]}
            return {k: walk(x, k) for k, x in v.items() if not (k == "timestamp" and isinstance(x, (int, str)) and x not in ("2026-09-01T00:00:00.000Z",))}
        if isinstance(v, list):
            return [walk(x) for x in v]
        if isinstance(v, str):
            return text(v)
        return v
    return walk(value)

expected = drive(UPSTREAM, [])
for label, extra, threads in (("native1", [], "1"), ("native4", [], "4")):
    actual = drive(NATIVE, extra, threads)
    for want, got in zip(expected, actual):
        # Upstream reads a missing field unchecked and reports the JavaScript
        # TypeError text; both must fail, the message is not reproduced.
        if want.get("id") in MALFORMED:
            assert want["success"] is False and got["success"] is False, (label, want, got)
            continue
        if want != got:
            import difflib
            diff = difflib.unified_diff(json.dumps(want, indent=1, sort_keys=True).split("\n"), json.dumps(got, indent=1, sort_keys=True).split("\n"), "pi", "bend", lineterm="")
            sys.exit(f"{label}: response {want.get('id')} differs\n" + "\n".join(diff))
    assert len(expected) == len(actual), label
    print(f"{label}: {len(expected)} RPC session-replacement responses match pi 0.87.1")
