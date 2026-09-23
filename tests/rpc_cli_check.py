"""Native RPC stdin, UTF-8 framing, response order and optional live prompt."""
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))


def command(threads, *args):
    return [str(CLI), "--threads", str(threads), "--", "--mode", "rpc", *args]


for threads in (1, 4):
    process = subprocess.Popen(command(threads, "--no-tools"), cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for chunk in (b'{"id":"\xc3', b'\xa9","type":"get_messages"}\r', b'\n{"id":"last","type":"get_messages"}'):
        process.stdin.write(chunk)
        process.stdin.flush()
        time.sleep(0.05)
    process.stdin.close()
    assert process.wait(timeout=30) == 0, process.stderr.read()
    replies = [json.loads(line) for line in process.stdout.read().splitlines()]
    assert [item["id"] for item in replies] == ["é", "last"], replies
    assert all(item["success"] and item["command"] == "get_messages" for item in replies), replies
    assert process.stderr.read() == b""
    print(f"native{threads}: streamed UTF-8 and final JSONL record")

invalid = subprocess.run(command(1, "--no-tools"), cwd=ROOT, input=b'{"id":"\xff","type":"get_messages"}\n', capture_output=True, timeout=30)
assert invalid.returncode == 1 and b"Invalid UTF-8 on RPC stdin" in invalid.stderr and not invalid.stdout
print("native1: malformed UTF-8 rejected")

files = subprocess.run(command(1, "@/tmp/no-such-prompt"), cwd=ROOT, input=b"", capture_output=True, timeout=30)
assert files.returncode == 1 and b"@file arguments are not supported in RPC mode" in files.stderr
print("native1: RPC rejects @file arguments")

if os.environ.get("PI_BEND_LIVE") == "1":
    payload = b'{"id":"prompt-1","type":"prompt","message":"What is seven plus eight? Reply with digits only."}\n'
    result = subprocess.run(command(4, "--provider", "openai", "--model", "gpt-4.1-mini", "--no-tools"), cwd=ROOT, input=payload, capture_output=True, timeout=90)
    events = [json.loads(line) for line in result.stdout.splitlines()]
    assistants = [event["message"] for event in events if event.get("type") == "message_end" and event.get("message", {}).get("role") == "assistant"]
    answer = "".join(part.get("text", "") for message in assistants for part in message.get("content", []) if isinstance(part, dict))
    assert result.returncode == 0 and events[0] == {"id": "prompt-1", "type": "response", "command": "prompt", "success": True}
    assert "agent_start" in [event.get("type") for event in events[1:]] and answer.strip() == "15", (answer, result.stderr)
    print("native4: live prompt acknowledged before model events and completed")
