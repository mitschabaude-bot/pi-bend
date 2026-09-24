"""Scenarios for tests/parity/runner.py.

Paths in `files` are relative to the scenario root (home/, project/). Steps:
  ("keys", text)  literal input      ("key", name)  tmux key name (Enter, C-o)
  ("wait", regex[, label])  record input→screen latency under `label`
  ("settle"[, seconds])     wait for a quiet screen   ("snap", name)
"""

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
]
