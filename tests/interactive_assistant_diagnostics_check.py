#!/usr/bin/env python3
"""Exercise Anthropic diagnostic details through the native CLI and its terminal."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time
from http.server import HTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parent / "parity"))
from runner import Terminal
from anthropic_client_loopback import Handler, event

ROOT = Path(__file__).resolve().parents[1]
MODEL = "parity-anthropic"
NOTICE = "Anthropic dropped 1 thinking block (details in session)"
TRANSFORMATION = {"type": "thinking_dropped", "path": "messages.1.content.0", "reason": "prefix_binding_mismatch"}


def response():
    return "".join([
        event("message_start", {"type": "message_start", "message": {"id": "m-diagnostic", "model": MODEL, "usage": {"input_tokens": 2, "output_tokens": 0}, "input_transformations": [TRANSFORMATION]}}),
        event("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
        event("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "survived"}}),
        event("content_block_stop", {"type": "content_block_stop", "index": 0}),
        event("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 1}}),
        event("message_stop", {"type": "message_stop"}),
    ]).encode()


def environment(root, port, enabled):
    agent = root / ".pi" / "agent"
    agent.mkdir(parents=True)
    model = {"id": MODEL, "name": MODEL, "reasoning": True, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 200000, "maxTokens": 8192}
    (agent / "models.json").write_text(json.dumps({"providers": {"anthropic": {"baseUrl": f"http://127.0.0.1:{port}/v1", "api": "anthropic-messages", "apiKey": "test-key", "models": [model]}}}))
    (agent / "settings.json").write_text(json.dumps({"showCacheMissNotices": enabled}))
    return {"HOME": str(root), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_BEND_PACKAGE_DIR": str(ROOT), "BEND_THREADS": os.environ.get("BEND_THREADS", "1"), "PATH": os.environ["PATH"], "TERM": "xterm-256color", "LANG": "C.UTF-8"}


def command(binary):
    return [str(binary), "--provider", "anthropic", "--model", MODEL, "--no-extensions", "--no-skills", "--no-prompt-templates"]


def assistant_details(message):
    return message["diagnostics"][0]["details"]["transformations"]


def print_and_session(binary, port, root):
    env = environment(root, port, True)
    result = subprocess.run(command(binary) + ["--mode", "json", "--print", "hello"], cwd=root, env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (result.stdout[-1000:], result.stderr)
    events = [json.loads(line) for line in result.stdout.splitlines()]
    messages = [event["message"] for event in events if event.get("type") == "message_end" and event.get("message", {}).get("role") == "assistant"]
    assert len(messages) == 1 and assistant_details(messages[0]) == [TRANSFORMATION], messages
    sessions = list((root / ".pi" / "agent" / "sessions").rglob("*.jsonl"))
    assert len(sessions) == 1, sessions
    entries = [json.loads(line) for line in sessions[0].read_text().splitlines()]
    stored = [entry["message"] for entry in entries if entry.get("type") == "message" and entry.get("message", {}).get("role") == "assistant"]
    assert len(stored) == 1 and assistant_details(stored[0]) == [TRANSFORMATION], stored


def wait_requests(count):
    deadline = time.monotonic() + 12
    while len(Handler.requests) < count and time.monotonic() < deadline:
        time.sleep(.01)
    assert len(Handler.requests) >= count, "provider request did not arrive"


def terminal_notice(binary, port, root, enabled, repeated):
    env = environment(root, port, enabled)
    terminal = Terminal(f"anthropic-diagnostic-{enabled}-{repeated}", command(binary), env, root)
    try:
        assert terminal.wait(MODEL + " • ", 10) is not None, terminal.screen()
        terminal.settle(1.5, 15)
        before = len(Handler.requests)
        terminal.keys("hello")
        terminal.key("Enter")
        wait_requests(before + 1)
        if enabled:
            assert terminal.wait(re.escape(NOTICE), 10) is not None, terminal.screen()
        else:
            terminal.settle(.5, 10)
            assert NOTICE not in terminal.screen(), terminal.screen()
        if repeated:
            terminal.keys("again")
            terminal.key("Enter")
            wait_requests(before + 2)
            terminal.settle(.5, 10)
            assert terminal.screen().count(NOTICE) == 1, terminal.screen()
    finally:
        terminal.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default="build/pi-cli")
    args = parser.parse_args()
    binary = (ROOT / args.binary).resolve()
    Handler.requests = []
    Handler.tool_mode = False
    Handler.response = response()
    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="pi-bend-diagnostics-") as directory:
            root = Path(directory)
            print_and_session(binary, server.server_port, root / "print")
            terminal_notice(binary, server.server_port, root / "enabled", True, True)
            terminal_notice(binary, server.server_port, root / "disabled", False, False)
        print("assistant diagnostic details, persistence, visible notice, disabled notice and deduplication pass")
    finally:
        server.shutdown()
        thread.join()


if __name__ == "__main__":
    main()
