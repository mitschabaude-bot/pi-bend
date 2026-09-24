"""Scenarios for tests/parity/runner.py.

Paths in `files` are relative to the scenario root (home/, project/). Steps:
  ("keys", text)  literal input      ("key", name)  tmux key name (Enter, C-o)
  ("wait", regex[, label])  record input→screen latency under `label`
  ("settle"[, seconds])     wait for a quiet screen   ("snap", name)
"""
import json

MODEL = ["--provider", "openai", "--model", "gpt-5"]
READY = r"gpt-5 • "  # the footer's model line: the editor is mounted

RESOURCES = {
    "home/.agents/skills/demo/SKILL.md": "---\nname: demo\ndescription: A demo skill for parity tests.\n---\nDo the demo.\n",
    "project/AGENTS.md": "# Project rules\n\nKeep answers short.\n",
}

def typed(word):
    """Type a word one key at a time, timing each key until it is painted."""
    steps = []
    for index in range(1, len(word) + 1):
        steps.append(("keys", word[index - 1]))
        steps.append(("wait", rf"(^|\s){word[:index]}(\s|$)", f"key{index}"))
    return steps

ANSWER = " ".join(f"word{index}" for index in range(1, 121)) + " END-OF-ANSWER"

SCENARIOS = [
    {
        "name": "startup",
        "args": MODEL,
        "files": RESOURCES,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("snap", "startup")],
    },
    {
        "name": "startup-help",
        "args": MODEL,
        "files": RESOURCES,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("key", "C-o"), ("settle", 0.5), ("snap", "expanded")],
    },
    {
        "name": "bash-env",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "!env | grep ^PI_ | sort"), ("key", "Enter"),
                  ("wait", r"PI_OFFLINE=1", "bash"), ("settle", 0.5), ("snap", "bash")],
    },
    {
        "name": "typing",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), *typed("parity"), ("settle", 0.3), ("snap", "typed")],
    },
    {
        "name": "basic-turn",
        "args": MODEL,
        "turns": [{"text": ANSWER, "chunks": 40, "delay_ms": 10, "usage": {"input": 1200, "output": 150}}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "hello"), ("key", "Enter"),
                  ("wait", r"word1\b", "first-token"), ("wait", "END-OF-ANSWER", "last-token"),
                  ("settle", 0.5), ("snap", "answered")],
    },
    {
        "name": "tool-call",
        "args": MODEL,
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "echo tool-output"}}}, {"text": "Tool finished."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "run it"), ("key", "Enter"),
                  ("wait", "Tool finished", "turn"), ("settle", 0.5), ("snap", "tool")],
    },
    {
        # On exit pi leaves its last frame, footer included, above the shell prompt.
        "name": "exit",
        "args": MODEL,
        "files": RESOURCES,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("key", "C-d"), ("settle", 1.0), ("snap", "exited")],
    },
    {
        "name": "shortcuts",
        "args": ["--provider", "openai", "--models", "gpt-5,gpt-5-mini"],
        "steps": [("wait", r"gpt-5 • ", "startup"), ("settle", 0.5),
                  ("key", "S-Tab"), ("settle", 0.5), ("snap", "thinking-cycled"),
                  ("key", "C-p"), ("settle", 0.5), ("snap", "model-cycled")],
    },
    {
        # models.json provider headers reach the request (upstream prepareRequest).
        "name": "provider-headers",
        "args": MODEL,
        "provider": {"headers": {"X-Team": "t1"}},
        "turns": [{"text": "Headers seen."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "hi"), ("key", "Enter"),
                  ("wait", "Headers seen", "turn"), ("settle", 0.5), ("snap", "answered")],
    },
    {
        "name": "print-turn",
        "process": True,
        "args": MODEL + ["-p", "hello"],
        "turns": [{"text": "Printed answer.", "chunks": 3, "usage": {"input": 900, "output": 20}}],
        "steps": [],
    },
    {
        "name": "print-tool",
        "process": True,
        "args": MODEL + ["-p", "run it"],
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "echo tool-output"}}}, {"text": "Tool finished."}],
        "steps": [],
    },
    {
        # The JSON event stream of one tool turn (timestamps and ids normalised).
        "name": "json-turn",
        "process": True,
        "args": MODEL + ["--mode", "json", "run it"],
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "echo tool-output"}}}, {"text": "Tool finished."}],
        "steps": [],
    },
    {"name": "cli-help", "process": True, "args": ["--help"], "steps": []},
    {"name": "cli-version", "process": True, "args": ["--version"], "steps": []},
    {"name": "cli-list-models", "process": True, "args": ["--list-models"], "steps": []},
    {"name": "cli-list-models-search", "process": True, "args": ["--list-models", "gpt-5"], "steps": []},
    {"name": "cli-unknown-model", "process": True, "args": ["--provider", "openai", "--model", "nope", "-p", "hi"], "steps": []},
    {"name": "cli-no-prompt-print", "process": True, "args": MODEL + ["-p"], "steps": []},
    {"name": "print-thinking-high", "process": True, "args": MODEL + ["--thinking", "high", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-model-suffix", "process": True, "args": ["--provider", "openai", "--model", "gpt-5:low", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-no-tools", "process": True, "args": MODEL + ["--no-tools", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-tools-subset", "process": True, "args": MODEL + ["--tools", "read,ls,grep", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-system-prompt", "process": True, "args": MODEL + ["--system-prompt", "You are terse.", "--append-system-prompt", "Always answer in English.", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-context-skills", "process": True, "args": MODEL + ["-p", "hi"], "files": RESOURCES, "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-file-arg", "process": True, "args": MODEL + ["-p", "@notes.txt", "summarise"], "files": {"project/notes.txt": "line one\nline two\n"}, "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-continue", "process": True, "before": [MODEL + ["-p", "first"]], "args": MODEL + ["-c", "-p", "second"],
     "turns": [{"text": "first answer"}, {"text": "second answer"}], "steps": []},
    {"name": "print-read-tool", "process": True, "args": MODEL + ["-p", "read it"], "files": {"project/data.txt": "alpha\nbeta\n"},
     "turns": [{"tool": {"name": "read", "arguments": {"path": "data.txt"}}}, {"text": "Read done."}], "steps": []},
    {"name": "print-http-400", "process": True, "args": MODEL + ["-p", "hi"],
     "turns": [{"status": 400, "error": {"error": {"message": "Invalid request: bad field", "type": "invalid_request_error"}}}], "steps": []},
    {"name": "print-retry-500", "process": True, "args": MODEL + ["-p", "hi"],
     "files": {"home/.pi/agent/settings.json": json.dumps({"retry": {"enabled": True, "maxRetries": 2, "baseDelayMs": 10}})},
     "turns": [{"status": 500}, {"text": "recovered"}], "steps": []},
    {"name": "print-failed", "process": True, "args": MODEL + ["-p", "hi"],
     "files": {"home/.pi/agent/settings.json": json.dumps({"retry": {"enabled": False}})},
     "turns": [{"failed": {"code": "server_error", "message": "boom"}}], "steps": []},
]
