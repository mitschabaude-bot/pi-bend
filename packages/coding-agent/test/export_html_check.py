"""Check the standalone viewer produced by export-html.bend after each backend run."""
import base64
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[3]
html = (root / "pi-session-export-html-source.html").read_text()
match = re.search(r'<script id="session-data" type="application/json">([A-Za-z0-9+/=]+)</script>', html)
assert match, "missing Base64 session payload"
data = json.loads(base64.b64decode(match.group(1)).decode("utf-8"))
assert data["header"]["id"] == "export-1"
assert data["leafId"] == "r1"
assert data["systemPrompt"] == "System instructions <safe>"
assert data["tools"] == []
assert len(data["entries"]) == 3
user, assistant, result = (entry["message"] for entry in data["entries"])
assert user["content"] == "<script>alert(1)</script> & é"
assert assistant["content"][0]["text"] == "I will run it."
assert assistant["content"][1]["name"] == "bash"
assert assistant["content"][1]["arguments"]["command"] == "printf '<script>'"
assert result["role"] == "toolResult"
assert result["content"][0]["text"] == "<ok>\n  indented"
assert "<script>alert(1)</script> & é" not in html
assert "function renderToolCall(call)" in html
assert "function renderEntry(entry)" in html
assert "function escapeHtml(text)" in html
assert "function sanitizeMarkdownUrl(value)" in html
assert "--userMessageBg: #343541;" in html
assert "{{SESSION_DATA}}" not in html and "{{CSS}}" not in html and "{{JS}}" not in html
assert "<script src=" not in html
print("PASS standalone viewer assets, Unicode payload, messages, tools, and safe insertion")

standalone_html = (root / "build/export-html-from-file.html").read_text()
standalone_match = re.search(r'<script id="session-data" type="application/json">([A-Za-z0-9+/=]+)</script>', standalone_html)
assert standalone_match, "missing file-export payload"
standalone = json.loads(base64.b64decode(standalone_match.group(1)).decode("utf-8"))
assert standalone["header"] == data["header"]
assert standalone["entries"] == data["entries"]
assert standalone["leafId"] == data["leafId"]
assert "systemPrompt" not in standalone and "tools" not in standalone
print("PASS standalone JSONL export preserves the full typed session")
