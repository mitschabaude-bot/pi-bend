#!/usr/bin/env python3
"""Source-pinned RPC settings and user bash lifecycle against pi-mono v0.87.1."""
from upstream_pin import UPSTREAM
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-mode.ts").read_bytes()).hexdigest() == "7d4bf1e4291a5320a1ce27504c488622c9a7307ce9e7c2d973f9d95f18a8b2bc"
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/core/agent-session.ts").read_bytes()).hexdigest() == "e5c020bced4ada5c5e116cbd160f66e111016fc717ae30d79994a45527e7f3d7"


def send(process, **request):
    process.stdin.write(json.dumps(request).encode() + b"\n")
    process.stdin.flush()


def until(process, predicate, timeout=15):
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        line = process.stdout.readline()
        assert line, ("early exit", process.poll(), process.stderr.read())
        item = json.loads(line)
        seen.append(item)
        if predicate(item):
            return item, seen
    raise AssertionError(("timeout", seen, process.poll()))


def check(label, command):
    with tempfile.TemporaryDirectory(prefix="rpc-controls-") as temporary:
        cwd = Path(temporary)
        agent = cwd / "agent"
        agent.mkdir()
        env = dict(os.environ, PI_FAUX_API_KEY="faux-key", PI_CODING_AGENT_DIR=str(agent), PI_CODING_AGENT_SESSION_DIR=str(cwd / "sessions"))
        process = subprocess.Popen(command + ["--mode", "rpc", "--no-session", "--no-tools"], cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        try:
            send(process, id="compaction", type="set_auto_compaction", enabled=False)
            assert until(process, lambda x: x.get("id") == "compaction")[0]["success"]
            send(process, id="retry", type="set_auto_retry", enabled=False)
            assert until(process, lambda x: x.get("id") == "retry")[0]["success"]
            send(process, id="steering", type="set_steering_mode", mode="all")
            assert until(process, lambda x: x.get("id") == "steering")[0]["success"]
            send(process, id="follow", type="set_follow_up_mode", mode="all")
            assert until(process, lambda x: x.get("id") == "follow")[0]["success"]
            send(process, id="bad-compaction", type="set_auto_compaction", enabled="false")
            assert until(process, lambda x: x.get("id") == "bad-compaction")[0]["error"] == "Invalid command: enabled must be a boolean"
            send(process, id="bad-retry", type="set_auto_retry", enabled="false")
            assert until(process, lambda x: x.get("id") == "bad-retry")[0]["error"] == "Invalid command: enabled must be a boolean"
            send(process, id="state", type="get_state")
            assert until(process, lambda x: x.get("id") == "state")[0]["data"]["autoCompactionEnabled"] is False
            send(process, id="bad", type="bash", command=1)
            assert until(process, lambda x: x.get("id") == "bad")[0]["success"] is False
            send(process, id="run", type="bash", command="printf 'hello\\n'", excludeFromContext=True)
            result, events = until(process, lambda x: x.get("id") == "run" and x.get("type") == "response")
            assert result["success"] and result["data"]["output"] == "hello\n", (result, events)
            assert result["data"]["cancelled"] is False and result["data"]["exitCode"] == 0
            send(process, id="messages", type="get_messages")
            messages = until(process, lambda x: x.get("id") == "messages")[0]["data"]["messages"]
            bash_messages = [m for m in messages if m.get("role") == "bashExecution"]
            assert len(bash_messages) == 1 and bash_messages[0]["command"] == "printf 'hello\\n'" and bash_messages[0].get("excludeFromContext") is True, messages
            send(process, id="entries", type="get_entries")
            entries = until(process, lambda x: x.get("id") == "entries")[0]["data"]["entries"]
            bash_entries = [entry["message"] for entry in entries if entry.get("type") == "message" and entry.get("message", {}).get("role") == "bashExecution"]
            assert len(bash_entries) == 1 and bash_entries[0] == bash_messages[0], entries
            send(process, id="long", type="bash", command="printf start; sleep 10")
            time.sleep(0.2)
            send(process, id="abort", type="abort_bash")
            aborted, before_abort = until(process, lambda x: x.get("id") == "abort")
            assert aborted["success"]
            assert any(x.get("type") == "bash_execution_update" and x.get("id") == "long" and "start" in x.get("delta", "") for x in before_abort), before_abort
            stopped, _ = until(process, lambda x: x.get("id") == "long" and x.get("type") == "response", timeout=5)
            assert stopped["success"] and stopped["data"]["cancelled"] is True and stopped["data"]["output"] == "start", stopped
            process.stdin.close()
            assert process.wait(timeout=10) == 0, process.stderr.read()
            saved = json.loads((agent / "settings.json").read_text())
            assert saved["retry"]["enabled"] is False and saved["steeringMode"] == "all" and saved["followUpMode"] == "all", saved
            print(f"{label}: settings persistence (including queue modes), bash history/events, and cancellation")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


for label, command in (("native1", ["env", "BEND_THREADS=1", str(ROOT / "build/rpc-controls-cli-native")]), ("native4", ["env", "BEND_THREADS=4", str(ROOT / "build/rpc-controls-cli-native")])):
    if os.environ.get("PI_BEND_ONLY", label) == label:
        check(label, command)
