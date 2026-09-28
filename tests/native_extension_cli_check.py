#!/usr/bin/env python3
"""Run a linked Bend extension through the ordinary pi-bend CLI and model loop."""
import json
import os
from pathlib import Path

from parity.runner import run_side
from parity.scenarios import MODEL


BINARY = Path(os.environ.get("PI_BEND_NATIVE_EXTENSION_CLI", "build/pi-cli-subagent")).resolve()


def run(args, turns=None, files=None):
    scenario = {
        "name": "native-extension-cli",
        "process": True,
        "args": MODEL + args,
        "turns": turns or [{"text": "ready"}],
        "files": files or {},
        "steps": [],
        "timeout": 45,
    }
    return run_side("bend", [str(BINARY)], scenario, False)


def tool_names(request):
    return [tool["name"] for tool in request["body"].get("tools", [])]


def check():
    baseline = run(["-p", "hello"])
    assert baseline["snaps"]["exit"] == "0", baseline["snaps"]
    assert "subagent" not in tool_names(json.loads(baseline["requests"])[0])

    enabled = run(["--extension", "subagent", "-p", "hello"])
    assert enabled["snaps"]["exit"] == "0", enabled["snaps"]
    assert "subagent" in tool_names(json.loads(enabled["requests"])[0])

    disabled = run(["--extension", "subagent", "--no-extensions", "-p", "hello"])
    assert disabled["snaps"]["exit"] == "0", disabled["snaps"]
    assert "subagent" in tool_names(json.loads(disabled["requests"])[0])

    unknown = run(["--extension", "not-linked", "-p", "hello"])
    assert unknown["snaps"]["exit"] != "0", unknown["snaps"]
    assert "not linked into this pi-bend build" in unknown["snaps"]["stderr"], unknown["snaps"]

    worker = "---\nname: worker\ndescription: Test child process\nmodel: openai/gpt-5\n---\nAnswer the task briefly.\n"
    delegated = run(
        ["--extension", "subagent", "-p", "delegate"],
        [
            {"tool": {"name": "subagent", "arguments": {"agent": "worker", "task": "Say CHILD-OK"}}},
            {"text": "CHILD-OK"},
            {"text": "PARENT-OK"},
        ],
        {"home/.pi/agent/agents/worker.md": worker},
    )
    requests = json.loads(delegated["requests"])
    assert delegated["snaps"]["exit"] == "0", delegated["snaps"]
    assert len(requests) == 3, (delegated["snaps"], requests)
    assert requests[1]["body"]["model"] == "gpt-5", requests[1]
    assert "Task: Say CHILD-OK" in json.dumps(requests[1]["body"]["input"]), requests[1]
    assert "CHILD-OK" in json.dumps(requests[2]["body"]["input"]), requests[2]
    assert "PARENT-OK" in delegated["snaps"]["stdout"], delegated["snaps"]
    print("native extension CLI: explicit registration, discovery switch, unknown name, child model request and return")


if __name__ == "__main__":
    check()
