#!/usr/bin/env python3
"""RPC flows run against installed pi and Bend pi with the scripted server.

Each step sends one command and waits for its response (and, for prompts,
for the agent to settle), because upstream handles RPC commands
concurrently. Responses, the session file and the model requests are
compared after the runner's normalisation.

  python3 tests/parity/rpc_flows.py [--bend build/pi-cli] [--only NAME]
"""
import argparse
import difflib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fake_openai  # noqa: E402
import runner  # noqa: E402

MODEL = ["--provider", "openai", "--model", "gpt-5"]
LONG = "word " * 400

FLOWS = [
    {
        "name": "compact",
        "turns": [{"text": "First answer. " + LONG, "usage": {"input": 3000, "output": 400}},
                  {"text": "Second answer.", "usage": {"input": 3500, "output": 20}},
                  {"text": "## Goal\nTalk.\n\n## Progress\nTwo answers given."}],
        "settings": {"compaction": {"keepRecentTokens": 1}},
        "steps": [
            {"type": "prompt", "message": "one"},
            {"type": "prompt", "message": "two"},
            {"type": "compact"},
            {"type": "get_state"},
            {"type": "get_messages"},
            {"type": "get_session_stats"},
        ],
    },
    {
        # A second compaction updates the previous summary (the update prompt).
        "name": "compact-twice",
        "turns": [{"text": "First answer. " + LONG, "usage": {"input": 3000, "output": 400}},
                  {"text": "## Goal\nTalk.\n\n## Progress\nOne answer."},
                  {"text": "Second answer. " + LONG, "usage": {"input": 3500, "output": 400}},
                  {"text": "## Goal\nTalk.\n\n## Progress\nTwo answers."}],
        "settings": {"compaction": {"keepRecentTokens": 1}},
        "steps": [
            {"type": "prompt", "message": "one"},
            {"type": "compact"},
            {"type": "prompt", "message": "two"},
            {"type": "compact", "customInstructions": "Keep it short."},
            {"type": "get_messages"},
        ],
    },
    {
        # A context overflow compacts and retries the prompt.
        "name": "overflow-retry",
        "turns": [{"text": "First answer. " + LONG, "usage": {"input": 3000, "output": 400}},
                  {"status": 400, "error": {"error": {"message": "Your input exceeds the context window of this model. Please adjust your input and try again.", "type": "invalid_request_error", "code": "context_length_exceeded"}}},
                  {"text": "## Goal\nTalk.\n\n## Progress\nOne answer."},
                  {"text": "Answer after compaction."}],
        "settings": {"compaction": {"keepRecentTokens": 1}},
        "steps": [
            {"type": "prompt", "message": "one"},
            {"type": "prompt", "message": "two"},
            {"type": "get_messages"},
        ],
    },
    {
        "name": "session-settings",
        "turns": [{"text": "Hi."}],
        "files": {"agent/prompts/review.md": "---\ndescription: Review a file\n---\nReview $1.\n",
                  "home/.agents/skills/demo/SKILL.md": "---\nname: demo\ndescription: A demo skill.\n---\nDo the demo.\n"},
        "steps": [
            {"type": "get_commands"},
            {"type": "set_steering_mode", "mode": "all"},
            {"type": "set_follow_up_mode", "mode": "all"},
            {"type": "set_auto_compaction", "enabled": False},
            {"type": "set_auto_retry", "enabled": False},
            {"type": "set_session_name", "name": "Parity flow"},
            {"type": "prompt", "message": "hello"},
            {"type": "get_fork_messages"},
            {"type": "get_last_assistant_text"},
            {"type": "get_state"},
            {"type": "abort_retry"},
            {"type": "abort_bash"},
            {"type": "abort"},
            {"type": "no_such_command"},
        ],
    },
    {
        "name": "bash",
        "turns": [{"text": "Saw it."}],
        "steps": [
            {"type": "bash", "command": "echo hello-from-bash"},
            {"type": "bash", "command": "exit 3"},
            {"type": "bash", "command": "echo hidden", "excludeFromContext": True},
            {"type": "prompt", "message": "what ran?"},
            {"type": "get_messages"},
        ],
    },
    {
        "name": "models",
        "turns": [],
        "steps": [
            {"type": "get_available_models"},
            {"type": "set_model", "provider": "openai", "modelId": "gpt-5-mini"},
            {"type": "get_available_thinking_levels"},
            {"type": "set_thinking_level", "level": "high"},
            {"type": "cycle_thinking_level"},
            {"type": "cycle_model"},
            {"type": "get_state"},
        ],
    },
    {
        "name": "follow-up",
        "turns": [{"text": "First.", "chunks": 20, "delay_ms": 20}, {"text": "Follow-up answer."}],
        "steps": [
            {"type": "prompt", "message": "one", "settle": False},
            {"type": "follow_up", "message": "and then this"},
            {"type": "wait_settled"},
            {"type": "get_last_assistant_text"},
            {"type": "get_messages"},
        ],
    },
    {
        "name": "steer-and-queue",
        "turns": [{"text": "Answer.", "chunks": 20, "delay_ms": 20}, {"text": "Steered answer."}],
        "steps": [
            {"type": "prompt", "message": "one", "settle": False},
            {"type": "steer", "message": "also this"},
            {"type": "wait_settled"},
            {"type": "get_messages"},
        ],
    },
]

def drive(label, argv, flow, keep):
    # Equal-length names: the cwd enters the system prompt and token estimates.
    root = Path(tempfile.mkdtemp(prefix=f"pi-rpc-flow-{label[0]}-"))
    home = root / "home"
    agent = home / ".pi" / "agent"
    project = root / "project"
    agent.mkdir(parents=True)
    project.mkdir()
    for relative, content in flow.get("files", {}).items():
        path = agent / relative[len("agent/"):] if relative.startswith("agent/") else root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    if "settings" in flow:
        (agent / "settings.json").write_text(json.dumps(flow["settings"]))
    log = root / "requests.jsonl"
    server = fake_openai.serve(flow["turns"], str(log))
    (agent / "models.json").write_text(json.dumps({"providers": {"openai": {"baseUrl": f"http://127.0.0.1:{server.server_address[1]}/v1"}}}))
    env = {"HOME": str(home), "PI_CODING_AGENT_DIR": str(agent), "PATH": os.environ["PATH"], "LANG": "C.UTF-8",
           "OPENAI_API_KEY": "sk-parity", "PI_OFFLINE": "1", **runner.package_links()}
    process = subprocess.Popen(argv + MODEL + ["--mode", "rpc"], cwd=project, env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    responses = []

    def read_until(predicate):
        while True:
            line = process.stdout.readline()
            assert line, (label, flow["name"], process.stderr.read()[-2000:])
            record = json.loads(line)
            if predicate(record):
                return record

    try:
        for index, step in enumerate(flow["steps"]):
            if step["type"] == "wait_settled":
                read_until(lambda r: r.get("type") == "agent_settled")
                continue
            command = {k: v for k, v in step.items() if k != "settle"}
            command["id"] = f"s{index}"
            process.stdin.write(json.dumps(command) + "\n")
            process.stdin.flush()
            responses.append(read_until(lambda r: r.get("type") == "response" and r.get("id") == command["id"]))
            if step["type"] == "prompt" and step.get("settle", True):
                read_until(lambda r: r.get("type") == "agent_settled")
    finally:
        process.stdin.close()
        process.wait(timeout=30)
        server.shutdown()
    port = f"127.0.0.1:{server.server_address[1]}"
    # The session directory name encodes the cwd path.
    encoded = "--" + str(project).strip("/").replace("/", "-") + "--"

    def clean(text):
        return runner.normalise(text.replace(port, "<server>").replace(encoded, "<cwd-dir>"), root)

    snaps = {"responses": clean(runner.normalise_events("\n".join(json.dumps(r) for r in responses)))}
    for index, path in enumerate(sorted((agent / "sessions").rglob("*.jsonl")) if (agent / "sessions").exists() else []):
        snaps[f"session{index}"] = clean(runner.normalise_events(path.read_text().rstrip("\n")))
    logged = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    for request in logged:
        request["headers"] = {k: v for k, v in request.get("headers", {}).items() if k not in runner.KNOWN_HEADERS}
    requests = runner.normalise(json.dumps(logged, indent=1, sort_keys=True), root)
    snaps["requests"] = runner.unpackage(requests).replace(
        f"127.0.0.1:{server.server_address[1]}", "<server>")
    if not keep:
        shutil.rmtree(root, ignore_errors=True)
    return snaps

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pi", default=shutil.which("pi") or "pi")
    parser.add_argument("--bend", default=str(runner.ROOT / "build/pi-cli"))
    parser.add_argument("--only")
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    out = runner.ROOT / "build/parity/rpc"
    failures = 0
    for flow in FLOWS:
        if args.only and flow["name"] != args.only:
            continue
        upstream = drive("pi", [args.pi], flow, args.keep)
        native = drive("bend", [str(Path(args.bend).resolve())], flow, args.keep)
        directory = out / flow["name"]
        directory.mkdir(parents=True, exist_ok=True)
        mismatched = []
        for name, expected in upstream.items():
            actual = native.get(name, "<missing>")
            (directory / f"{name}.pi.txt").write_text(expected + "\n")
            (directory / f"{name}.bend.txt").write_text(actual + "\n")
            if expected != actual:
                mismatched.append(name)
                (directory / f"{name}.diff").write_text("\n".join(difflib.unified_diff(expected.split("\n"), actual.split("\n"), "pi", "bend", lineterm="")) + "\n")
        failures += bool(mismatched)
        print(f"{flow['name']:<20} {'MATCH' if not mismatched else 'DIFF ' + ','.join(mismatched)}")
    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit(main())
