"""Scenarios for tests/parity/runner.py.

Paths in `files` are relative to the scenario root (home/, project/). Steps:
  ("keys", text)  literal input      ("key", name)  tmux key name (Enter, C-o)
  ("wait", regex[, label])  record input→screen latency under `label`
  ("settle"[, seconds])     wait for a quiet screen   ("snap", name)
  ("write", path, text)     change a file under the scenario root
"""
import base64
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
                  ("wait", r"word1\b", "first-token"), ("snap", "working"), ("wait", "END-OF-ANSWER", "last-token"),
                  ("settle", 0.5), ("snap", "answered")],
    },
    {
        "name": "tool-call",
        "args": MODEL,
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "echo tool-output"}}, "start_delay_ms": 1000}, {"text": "Tool finished."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "run it"), ("key", "Enter"),
                  ("wait", "Working", "working"), ("snap", "working"),
                  ("wait", "Tool finished", "turn"), ("settle", 0.5), ("snap", "tool")],
    },
    {
        "name": "copy",
        "args": MODEL,
        "turns": [{"text": "Copy me."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "/copy"), ("key", "Enter"),
                  ("wait", "No agent messages to copy yet", "empty"), ("snap", "empty"),
                  ("keys", "hello"), ("key", "Enter"),
                  ("wait", "Copy me.", "answer"), ("settle", 0.5),
                  ("keys", "/copy"), ("key", "Enter"),
                  ("wait", "Copied last agent message", "copied"), ("snap", "copied")],
    },
    {
        "name": "settings",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "/settings"), ("key", "Enter"),
                  ("wait", "Auto-compact", "panel"), ("settle", 0.2), ("snap", "panel"),
                  ("key", "Enter"), ("wait", r"Auto-compact\s+false", "changed"),
                  ("settle", 0.2), ("snap", "changed"),
                  ("key", "Escape"), ("settle", 0.2), ("snap", "closed")],
    },
    {
        # On exit pi leaves its last frame, footer included, above the shell prompt.
        "name": "exit",
        "args": MODEL,
        "files": RESOURCES,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("key", "C-d"), ("settle", 1.0), ("snap", "exited")],
    },
    {
        # /changelog lists every entry, oldest first; the screen shows the newest.
        "name": "changelog-command",
        "args": MODEL,
        "timeout": 60,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "/changelog"), ("key", "Enter"),
                  ("wait", "outdated Claude Code version", "changelog"), ("settle", 1.0), ("snap", "changelog")],
    },
    {
        # After an update, the entries newer than lastChangelogVersion are shown.
        "name": "whats-new",
        "args": MODEL,
        "files": {"home/.pi/agent/settings.json": json.dumps({"lastChangelogVersion": "0.86.0"})},
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("snap", "startup")],
    },
    {
        # /reload picks up edited context files and skills for the next request.
        "name": "reload",
        "args": MODEL,
        "files": RESOURCES,
        "turns": [{"text": "Reloaded answer."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("write", "project/AGENTS.md", "# Project rules\n\nAnswer in haiku.\n"),
                  ("write", "home/.agents/skills/extra/SKILL.md", "---\nname: extra\ndescription: Another skill.\n---\nMore.\n"),
                  ("keys", "/reload"), ("key", "Enter"), ("wait", "Reloaded keybindings", "reload"), ("settle", 0.5), ("snap", "reloaded"),
                  ("keys", "hi"), ("key", "Enter"), ("wait", "Reloaded answer", "turn"), ("settle", 0.5), ("snap", "answered")],
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
    {"name": "print-name", "process": True, "args": MODEL + ["--name", "Parity run", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-session-id", "process": True, "args": MODEL + ["--session-id", "parity-session", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-no-session", "process": True, "args": MODEL + ["--no-session", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-exclude-tools", "process": True, "args": MODEL + ["--exclude-tools", "bash,write", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-dash-message", "process": True, "args": MODEL + ["-p", "--", "- a point"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-two-messages", "process": True, "args": MODEL + ["-p", "first", "second"], "turns": [{"text": "one"}, {"text": "two"}], "steps": []},
    {"name": "print-template", "process": True, "args": MODEL + ["-p", "/review src/app.ts carefully"],
     "files": {"home/.pi/agent/prompts/review.md": "---\ndescription: Review a file\n---\nReview $1 and be $2. All: $ARGUMENTS\n"},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-skill-command", "process": True, "args": MODEL + ["-p", "/skill:demo now"], "files": RESOURCES, "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-edit-tool", "process": True, "args": MODEL + ["-p", "edit it"], "files": {"project/data.txt": "alpha\nbeta\n"},
     "turns": [{"tool": {"name": "edit", "arguments": {"path": "data.txt", "edits": [{"oldText": "beta", "newText": "gamma"}]}}}, {"text": "Edited."}], "steps": []},
    {"name": "print-edit-missing", "process": True, "args": MODEL + ["-p", "edit it"], "files": {"project/data.txt": "alpha\n"},
     "turns": [{"tool": {"name": "edit", "arguments": {"path": "data.txt", "edits": [{"oldText": "zeta", "newText": "gamma"}]}}}, {"text": "Failed."}], "steps": []},
    {"name": "print-write-tool", "process": True, "args": MODEL + ["-p", "write it"],
     "turns": [{"tool": {"name": "write", "arguments": {"path": "sub/new.txt", "content": "fresh\n"}}}, {"text": "Written."}], "steps": []},
    {"name": "print-bash-fail", "process": True, "args": MODEL + ["-p", "run it"],
     "turns": [{"tool": {"name": "bash", "arguments": {"command": "echo out; echo err >&2; exit 4"}}}, {"text": "Failed."}], "steps": []},
    {"name": "print-unknown-tool", "process": True, "args": MODEL + ["-p", "run it"],
     "turns": [{"tool": {"name": "nosuch", "arguments": {}}}, {"text": "Hm."}], "steps": []},
    {"name": "print-bad-args", "process": True, "args": MODEL + ["-p", "read it"],
     "turns": [{"tool": {"name": "read", "arguments": {"offset": "x"}}}, {"text": "Hm."}], "steps": []},
    {"name": "print-untrusted-project", "process": True, "args": MODEL + ["-p", "/proj hello"],
     "files": {"project/.pi/prompts/proj.md": "Project prompt: $1\n", "project/.pi/settings.json": json.dumps({"defaultThinkingLevel": "high"})},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-approved-project", "process": True, "args": MODEL + ["--approve", "-p", "/proj hello"],
     "files": {"project/.pi/prompts/proj.md": "Project prompt: $1\n", "project/.pi/settings.json": json.dumps({"defaultThinkingLevel": "high"})},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-default-trust", "process": True, "args": MODEL + ["-p", "/proj hello"],
     "files": {"project/.pi/prompts/proj.md": "Project prompt: $1\n", "home/.pi/agent/settings.json": json.dumps({"defaultProjectTrust": "always"})},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-saved-trust", "process": True, "args": MODEL + ["-p", "/proj hello"],
     "files": {"project/.pi/prompts/proj.md": "Project prompt: $1\n", "home/.pi/agent/trust.json": json.dumps({"<root>": True, "<root>/project": False})},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-saved-parent-trust", "process": True, "args": MODEL + ["-p", "/proj hello"],
     "files": {"project/.pi/prompts/proj.md": "Project prompt: $1\n", "home/.pi/agent/trust.json": json.dumps({"<root>": True})},
     "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-session-reuse", "process": True, "before": [MODEL + ["--session-id", "abc-reuse", "-p", "first"]],
     "args": MODEL + ["--session-id", "abc-reuse", "-p", "second"], "turns": [{"text": "one"}, {"text": "two"}], "steps": []},
    {"name": "print-session-partial", "process": True, "before": [MODEL + ["--session-id", "abc-partial", "-p", "first"]],
     "args": MODEL + ["--session", "abc-par", "-p", "second"], "turns": [{"text": "one"}, {"text": "two"}], "steps": []},
    {"name": "print-fork", "process": True, "before": [MODEL + ["--session-id", "abc-fork", "-p", "first"]],
     "args": MODEL + ["--fork", "abc-fork", "-p", "second"], "turns": [{"text": "one"}, {"text": "two"}], "steps": []},
    {"name": "print-session-missing", "process": True, "args": MODEL + ["--session", "nothing-here", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-fork-conflict", "process": True, "args": MODEL + ["--fork", "x", "--no-session", "-p", "hi"], "steps": []},
    {"name": "print-session-dir", "process": True, "args": MODEL + ["--session-dir", "sessions-here", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-image-file", "process": True, "args": MODEL + ["-p", "@pixel.png", "what is it"],
     "files": {"project/pixel.png": base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")}, "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-missing-file", "process": True, "args": MODEL + ["-p", "@nope.txt", "x"], "steps": []},
    {"name": "print-bad-thinking", "process": True, "args": MODEL + ["--thinking", "huge", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-unknown-flag", "process": True, "args": MODEL + ["--frobnicate", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-bad-mode", "process": True, "args": MODEL + ["--mode", "yaml", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-api-key", "process": True, "args": MODEL + ["--api-key", "sk-other", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-no-context", "process": True, "args": MODEL + ["-nc", "-ns", "-p", "hi"], "files": RESOURCES, "turns": [{"text": "ok"}], "steps": []},
]
