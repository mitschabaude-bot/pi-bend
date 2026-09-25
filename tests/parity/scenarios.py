"""Scenarios for tests/parity/runner.py.

Paths in `files` are relative to the scenario root (home/, project/). Steps:
  ("keys", text)  literal input      ("key", name)  tmux key name (Enter, C-o)
  ("wait", regex[, label])  record input→screen latency under `label`
  ("settle"[, seconds])     wait for a quiet screen   ("snap", name)
  ("write", path, text)     change a file under the scenario root
"""
import base64
import json
import os
import shutil

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

# @ file completion needs fd (pi's fdPath); scenarios that use it put the
# directory of an installed fd on PATH.
FD = shutil.which("fd") or os.path.expanduser("~/.pi/agent/bin/fd")
FD_PATH = {"PATH": os.path.dirname(FD) + ":" + os.environ.get("PATH", "")}

CODE_ANSWER = """Here is the code:

```typescript
interface Point { x: number; y: number }
// Distance between two points.
export function distance(a: Point, b: Point): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}
const origin: Point = { x: 0, y: 0 };
console.log(`distance: ${distance(origin, { x: 3, y: 4 })}`);
```

```python
def fib(n: int) -> int:
    \"\"\"Return the n-th Fibonacci number.\"\"\"
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

END-OF-CODE"""

ANSWER = " ".join(f"word{index}" for index in range(1, 121)) + " END-OF-ANSWER"

# A long Markdown answer for the streaming benchmark: paragraphs, lists,
# emphasis and highlighted code, about 11 KB.
def stream_section(index):
    return (f"## Section {index}\n\nParagraph {index} explains **step {index}** of the plan in plain words, "
            f"with `inline code`, a [link](https://example.com/{index}) and enough text to wrap across the terminal width twice over.\n\n"
            f"- first point of section {index}\n- second point, *emphasised*\n- third point\n\n"
            f"```python\ndef step_{index}(values):\n    return [value * {index} for value in values if value > 0]\n```\n\n")
STREAM_ANSWER = "STREAM-START\n\n" + "".join(stream_section(index) for index in range(1, 31)) + "END-OF-STREAM"

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
        "name": "trust-interactive",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}"},
        "trust_file": True,
        "steps": [("wait", "Trust project folder?", "prompt"), ("settle", 0.2), ("snap", "prompt"),
                  ("key", "Enter"), ("wait", READY, "accepted"), ("settle", 0.2), ("snap", "accepted")],
    },
    {
        "name": "trust-light-256",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}", "home/.pi/agent/settings.json": json.dumps({"theme": "light", "terminal": {"trueColor": False}})},
        "trust_file": True,
        "steps": [("wait", "Trust project folder?", "prompt"), ("settle", 0.2), ("snap", "prompt"),
                  ("key", "Enter"), ("wait", READY, "accepted"), ("settle", 0.2), ("snap", "accepted")],
    },
    {
        "name": "trust-session-only",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}"},
        "trust_file": True,
        "steps": [("wait", "Trust project folder?", "prompt"), ("key", "Down"), ("key", "Down"),
                  ("settle", 0.2), ("snap", "choice"), ("key", "Enter"),
                  ("wait", READY, "accepted"), ("settle", 0.2), ("snap", "accepted")],
    },
    {
        "name": "trust-decline",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}"},
        "trust_file": True,
        "steps": [("wait", "Trust project folder?", "prompt"), ("key", "Down"), ("key", "Down"),
                  ("key", "Down"), ("settle", 0.2), ("snap", "choice"), ("key", "Enter"),
                  ("wait", READY, "declined"), ("settle", 0.2), ("snap", "declined")],
    },
    {
        "name": "trust-command",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}", "home/.pi/agent/trust.json": json.dumps({"<root>/project": False})},
        "trust_file": True,
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/trust"), ("key", "Enter"),
                  ("wait", "Saved decision: untrusted", "selector"), ("settle", 0.2), ("snap", "selector"),
                  ("key", "Up"), ("key", "Up"), ("key", "Enter"),
                  ("wait", "Saved trust decision: trusted", "saved"), ("settle", 0.2), ("snap", "saved")],
    },
    {
        "name": "trust-command-cancel",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}", "home/.pi/agent/trust.json": json.dumps({"<root>/project": False})},
        "trust_file": True,
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/trust"), ("key", "Enter"),
                  ("wait", "Saved decision: untrusted", "selector"), ("key", "Escape"),
                  ("settle", 0.2), ("snap", "cancelled")],
    },
    {
        "name": "trust-custom-bindings",
        "args": MODEL,
        "files": {"project/.pi/settings.json": "{}", "home/.pi/agent/trust.json": json.dumps({"<root>/project": False}),
                  "home/.pi/agent/keybindings.json": json.dumps({"tui.select.down": "ctrl+n"})},
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/trust"), ("key", "Enter"),
                  ("wait", "Saved decision: untrusted", "selector"), ("key", "Up"), ("key", "Up"),
                  ("key", "Down"), ("settle", 0.2), ("snap", "default-key"),
                  ("key", "C-n"), ("settle", 0.2), ("snap", "custom-key")],
    },
    {
        "name": "trust-on-reload",
        "args": MODEL,
        "trust_file": True,
        "steps": [("wait", READY, "startup"), ("settle", 0.3),
                  ("write", "project/.pi/settings.json", "{}"),
                  ("keys", "/reload"), ("key", "Enter"),
                  ("wait", "saved project trust", "reloaded"), ("settle", 0.2), ("snap", "reloaded")],
    },
    {
        "name": "bash-env",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "!env | grep ^PI_ | sort"), ("key", "Enter"),
                  ("wait", r"PI_OFFLINE=1", "bash"), ("settle", 0.5), ("snap", "bash")],
    },
    {
        # upstream BashExecutionComponent: running loader, collapsed preview of
        # the last 20 lines with its expand hint, output without a final
        # newline, and a failing exit code.
        "name": "bash-shapes",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "!sleep 2; echo done"), ("key", "Enter"),
                  ("wait", "Running", "running"), ("snap", "running"),
                  ("wait", r"^ *done", "done"), ("settle", 0.3),
                  ("keys", "!seq 30"), ("key", "Enter"), ("wait", r"^ *30", "seq"), ("settle", 0.3), ("snap", "seq"),
                  ("key", "C-o"), ("settle", 0.5), ("snap", "expanded"), ("key", "C-o"), ("settle", 0.3),
                  ("keys", "!printf tail; exit 3"), ("key", "Enter"), ("wait", r"exit 3\)", "failed"), ("settle", 0.3), ("snap", "failed")],
    },
    {
        # Collapsed tool output and its expand hints (bash and read renderers).
        "name": "tool-previews",
        "args": MODEL,
        "files": {"project/data.txt": "".join(f"line {n}\n" for n in range(1, 41))},
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "seq 40"}}},
                  {"tool": {"name": "read", "arguments": {"path": "data.txt"}}}, {"text": "Both done."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "go"), ("key", "Enter"),
                  ("wait", "Both done", "turn"), ("settle", 0.5), ("snap", "collapsed"),
                  ("key", "C-o"), ("settle", 0.5), ("snap", "expanded")],
    },
    {
        "name": "listing-tool-calls",
        "args": MODEL + ["--tools", "read,bash,edit,write,find,grep,ls"],
        "files": {"project/items/one.txt": "needle one\n", "project/items/two.txt": "other two\n",
                  "project/items/other.md": "no match\n"},
        "turns": [{"tool": {"name": "find", "arguments": {"pattern": "*.txt", "path": "items"}}},
                  {"tool": {"name": "grep", "arguments": {"pattern": "needle", "path": "items"}}},
                  {"tool": {"name": "ls", "arguments": {"path": "items"}}},
                  {"text": "Search complete."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "search"), ("key", "Enter"),
                  ("wait", "Search complete", "turn"), ("settle", 0.5), ("snap", "collapsed")],
    },
    {
        "name": "bash-timeout",
        "args": MODEL,
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "printf ready", "timeout": 5}}}, {"text": "Done."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "run"), ("key", "Enter"),
                  ("wait", "Done.", "turn"), ("settle", 0.5), ("snap", "timed")],
    },
    {
        "name": "bash-truncated",
        "args": MODEL,
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "seq 2101"}}}, {"text": "Done."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "run"), ("key", "Enter"),
                  ("wait", "Done.", "turn"), ("settle", 0.5), ("snap", "truncated")],
    },
    {
        "name": "ls-preview",
        "args": MODEL + ["--tools", "ls"],
        "files": {f"project/items/file-{n:02}.txt": "data\n" for n in range(1, 26)},
        "turns": [{"tool": {"name": "ls", "arguments": {"path": "items"}}}, {"text": "Listed."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "list"), ("key", "Enter"),
                  ("wait", "Listed.", "turn"), ("settle", 0.5), ("snap", "collapsed"),
                  ("key", "C-o"), ("settle", 0.5), ("snap", "expanded")],
    },
    {
        "name": "ls-limit",
        "args": MODEL + ["--tools", "ls"],
        "files": {f"project/items/file-{n:02}.txt": "data\n" for n in range(1, 6)},
        "turns": [{"tool": {"name": "ls", "arguments": {"path": "items", "limit": 3}}}, {"text": "Listed."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "list"), ("key", "Enter"),
                  ("wait", "Listed.", "turn"), ("settle", 0.5), ("snap", "limited")],
    },
    {
        "name": "edit-preview",
        "args": MODEL,
        "files": {"project/note.txt": "alpha\nbeta\n"},
        "turns": [{"tool": {"name": "edit", "arguments": {"path": "note.txt", "edits": [{"oldText": "beta", "newText": "gamma"}]}}},
                  {"text": "Updated."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "update"), ("key", "Enter"),
                  ("wait", "Updated.", "turn"), ("settle", 0.5), ("snap", "edited")],
    },
    {
        "name": "typing",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.5), *typed("parity"), ("settle", 0.3), ("snap", "typed")],
    },
    {
        "name": "hotkeys",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/hotkeys"), ("key", "Enter"),
                  ("wait", "Run bash command \\(excluded from context\\)", "hotkeys"), ("settle", 0.3), ("snap", "hotkeys")],
    },
    {
        "name": "hotkeys-custom-binding",
        "args": MODEL,
        "files": {"home/.pi/agent/keybindings.json": json.dumps({"app.model.select": "ctrl+k"})},
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/hotkeys"), ("key", "Enter"),
                  ("wait", "Run bash command \\(excluded from context\\)", "hotkeys"), ("settle", 0.3), ("snap", "hotkeys"),
                  ("key", "C-k"), ("wait", "Only showing models", "picker"), ("settle", 0.3), ("snap", "picker")],
    },
    # Editor autocomplete: slash commands (skills rank by bare name), @ after
    # CJK punctuation, and Tab path completion after CJK punctuation.
    {
        "name": "autocomplete-slash",
        "args": MODEL,
        "files": {**RESOURCES, "home/.agents/skills/research-idea/SKILL.md": "---\nname: research-idea\ndescription: Refine an idea.\n---\nRefine.\n"},
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/idea"), ("wait", "research-idea", "popup"), ("settle", 0.3), ("snap", "idea"),
                  ("key", "C-u"), ("keys", "/mo"), ("wait", "model", "popup2"), ("settle", 0.3), ("snap", "mo")],
    },
    {
        "name": "autocomplete-at-cjk",
        "args": MODEL,
        "env": FD_PATH,
        "files": {"project/说明.md": "text\n", "project/文档/说明.md": "nested\n", "project/README.md": "readme\n"},
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "查看，@说"), ("wait", "说明.md", "popup"), ("settle", 0.3), ("snap", "popup"),
                  ("key", "Tab"), ("settle", 0.5), ("snap", "accepted"),
                  ("key", "C-u"), ("keys", "查看@REA"), ("settle", 0.8), ("snap", "letters")],
    },
    {
        "name": "autocomplete-tab-cjk",
        "args": MODEL,
        "files": {"project/文档/说明.md": "nested\n"},
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "查看。文"), ("key", "Tab"), ("settle", 0.8), ("snap", "directory"),
                  ("keys", "说"), ("key", "Tab"), ("settle", 0.8), ("snap", "file")],
    },
    # Typing latency with a large resumed session on screen (upstream's
    # large-session fixture: ~1000 entries).
    {
        "name": "large-session-typing",
        "args": MODEL + ["--session", "large.jsonl"],
        "files": {"project/large.jsonl": open("/home/agent/code/pi-mono/packages/coding-agent/test/fixtures/large-session.jsonl").read()},
        "steps": [("wait", "Continue", "prompt"), ("key", "Enter"), ("wait", READY, "startup"), ("settle", 1.0), *typed("typing"), ("settle", 0.3), ("snap", "typed")],
    },
    # A stored session whose cwd is gone: interactive mode asks (upstream
    # promptForMissingSessionCwd); Cancel exits quietly.
    {
        "name": "session-missing-cwd",
        "args": MODEL + ["--session", "large.jsonl"],
        "files": {"project/large.jsonl": open("/home/agent/code/pi-mono/packages/coding-agent/test/fixtures/large-session.jsonl").read()},
        "steps": [("wait", "Continue", "prompt"), ("settle", 0.3), ("snap", "prompt"), ("key", "Down"), ("key", "Enter"), ("settle", 1.0), ("snap", "cancelled")],
    },
    {
        "name": "basic-turn",
        "args": MODEL,
        "turns": [{"text": ANSWER, "chunks": 40, "delay_ms": 10, "usage": {"input": 1200, "output": 150}}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "hello"), ("key", "Enter"),
                  ("wait", r"word1\b", "first-token"), ("snap", "working"), ("wait", "END-OF-ANSWER", "last-token"),
                  ("settle", 0.5), ("snap", "answered")],
    },
    # Streaming benchmark over each CLI's own TLS stack: a long Markdown answer
    # in 500 deltas, paced (about 250 per second) and as fast as the server
    # writes. Bend may take at most 1.25x pi's time to render the last token.
    {
        "name": "stream-paced",
        "args": MODEL, "tls": True, "timeout": 60,
        "turns": [{"text": STREAM_ANSWER, "chunks": 500, "delay_ms": 4}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "stream"), ("key", "Enter"),
                  ("wait", r"STREAM-START", "first-token"), ("wait", "END-OF-STREAM", "last-token"),
                  ("settle", 0.5), ("snap", "answered")],
        "within": {"last-token": 1.25},
    },
    {
        "name": "stream-flood",
        "args": MODEL, "tls": True, "timeout": 60,
        "turns": [{"text": STREAM_ANSWER, "chunks": 500}],
        # The start scrolls away faster than the screen is polled.
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "stream"), ("key", "Enter"),
                  ("wait", "END-OF-STREAM", "last-token"),
                  ("settle", 0.5), ("snap", "answered")],
        "within": {"last-token": 1.25},
    },
    # Highlighted code blocks in an answer, then typing with them on screen.
    {
        "name": "code-answer",
        "args": MODEL,
        "turns": [{"text": CODE_ANSWER}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "code"), ("key", "Enter"),
                  ("wait", "END-OF-CODE", "answer"), ("settle", 0.5), ("snap", "answer"), *typed("more"), ("settle", 0.3), ("snap", "typed")],
    },
    {
        "name": "new-session",
        "args": MODEL,
        "turns": [{"text": "First answer."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "hello"), ("key", "Enter"),
                  ("wait", "First answer.", "answer"), ("settle", 0.5),
                  ("keys", "/new"), ("key", "Enter"),
                  ("wait", "New session started", "new"), ("settle", 0.2), ("snap", "after")],
    },
    {
        "name": "clone-session",
        "args": MODEL,
        "turns": [{"text": "First answer."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "hello"), ("key", "Enter"),
                  ("wait", "First answer.", "answer"), ("settle", 0.5),
                  ("keys", "/clone"), ("key", "Enter"),
                  ("wait", "Cloned to new session", "clone"), ("settle", 0.2), ("snap", "after")],
    },
    {
        "name": "clone-empty-error",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/clone"), ("key", "Enter"),
                  ("wait", "This session has not been saved yet", "error"), ("settle", 0.3), ("snap", "after")],
    },
    {
        "name": "thinking-invalid-error",
        "args": MODEL,
        "steps": [("wait", READY, "startup"), ("settle", 0.3), ("keys", "/thinking bogus"), ("key", "Enter"),
                  ("wait", "Error:", "error"), ("settle", 0.3), ("snap", "after")],
    },
    {
        "name": "thinking-selector",
        "args": MODEL,
        "env": FD_PATH,
        "steps": [("wait", READY, "startup"), ("settle", 1.0),
                  ("keys", "/thinking"), ("key", "Enter"), ("wait", "Thinking Level", "open"),
                  ("settle", 0.2), ("snap", "open"),
                  ("keys", "high"), ("settle", 0.2), ("snap", "filtered"),
                  ("key", "Enter"), ("wait", "Thinking level: high", "selected"),
                  ("settle", 0.2), ("snap", "selected"),
                  ("keys", "/thinking"), ("key", "Enter"), ("wait", "Thinking Level", "reopen"),
                  ("key", "C-s"), ("wait", "Default thinking level:", "saved"),
                  ("settle", 0.2), ("snap", "saved")],
    },
    {
        "name": "scoped-models-selector",
        "args": MODEL,
        "env": FD_PATH,
        "steps": [("wait", READY, "startup"), ("settle", 1.0),
                  ("keys", "/scoped-models"), ("key", "Enter"),
                  ("wait", "Model Configuration", "open"), ("settle", 0.3), ("snap", "open"),
                  ("keys", "gpt-5-mini"), ("settle", 0.2), ("snap", "filtered"),
                  ("key", "Enter"), ("settle", 0.2), ("snap", "toggled"),
                  ("key", "C-s"), ("wait", "Model selection saved to settings", "saved"),
                  ("settle", 0.2), ("snap", "saved"),
                  ("key", "Escape"), ("settle", 0.2), ("snap", "closed"),
                  ("key", "C-p"), ("settle", 0.2), ("snap", "cycled")],
    },
    {
        "name": "scoped-models-controls",
        "args": MODEL,
        "env": FD_PATH,
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "/scoped-models"), ("key", "Enter"),
                  ("wait", "Model Configuration", "open"),
                  ("key", "C-x"), ("settle", 0.2), ("snap", "cleared"),
                  ("key", "C-a"), ("settle", 0.2), ("snap", "enabled"),
                  ("key", "C-p"), ("settle", 0.2), ("snap", "provider"),
                  ("key", "Escape"), ("settle", 0.2), ("snap", "closed")],
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
        "name": "bash-preview-wrapped",
        "args": MODEL,
        "env": FD_PATH,
        "turns": [{"tool": {"name": "bash", "arguments": {"command": "python3 -c 'for n in range(1, 13): print(f\"line{n:02} \" + \"x\" * 110)'"}}},
                  {"text": "Preview done."}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5), ("keys", "show the output"), ("key", "Enter"),
                  ("wait", "Preview done", "done"), ("settle", 0.3), ("snap", "preview")],
    },
    {
        # upstream handleSessionCommand: counts, cached/uncached prompt split
        # and cost after two turns (the second with cache reads).
        "name": "session-info",
        "args": MODEL,
        "turns": [{"text": "First.", "usage": {"input": 1500, "output": 20}},
                  {"text": "Second.", "usage": {"input": 1500, "output": 40, "cacheRead": 1200}}],
        "steps": [("wait", READY, "startup"), ("settle", 0.5),
                  ("keys", "one"), ("key", "Enter"), ("wait", "First\\.", "first"), ("settle", 0.3),
                  ("keys", "two"), ("key", "Enter"), ("wait", "Second\\.", "second"), ("settle", 0.3),
                  ("keys", "/session"), ("key", "Enter"), ("wait", "Session Info", "info"), ("settle", 0.3), ("snap", "info")],
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
        # Pi uses the target model's saved level, then the global default,
        # before retaining the current level during a model switch.
        "name": "model-cycle-default-thinking",
        "args": ["--provider", "openai", "--models", "gpt-5,gpt-5-mini", "--thinking", "low"],
        "files": {"home/.pi/agent/settings.json": json.dumps({
            "defaultProvider": "openai", "defaultModel": "gpt-5", "defaultThinkingLevel": "high"})},
        "steps": [("wait", r"gpt-5 • low", "startup"), ("settle", 0.3), ("snap", "before"),
                  ("key", "C-p"), ("wait", r"gpt-5-mini • high", "cycled"),
                  ("settle", 0.3), ("snap", "after")],
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
    {"name": "cli-unknown-provider", "process": True, "args": ["--provider", "nosuch", "--model", "x", "-p", "hi"], "steps": []},
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
    # A bare id listed by several providers: the sole authenticated one wins,
    # otherwise the id is ambiguous (upstream resolveCliModel).
    {"name": "print-bare-authed", "process": True, "args": ["--model", "gpt-5", "-p", "hi"], "turns": [{"text": "ok"}], "steps": []},
    {"name": "print-bare-unauthed", "process": True, "args": ["--model", "gpt-5", "-p", "hi"], "env": {"OPENAI_API_KEY": ""}, "steps": []},
    {"name": "print-bare-two-authed", "process": True, "args": ["--model", "gpt-5", "-p", "hi"], "env": {"OPENROUTER_API_KEY": "sk-x", "AZURE_OPENAI_API_KEY": "sk-y"}, "steps": []},
    {"name": "print-no-context", "process": True, "args": MODEL + ["-nc", "-ns", "-p", "hi"], "files": RESOURCES, "turns": [{"text": "ok"}], "steps": []},
]
