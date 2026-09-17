"""Exercise native agent/tool/session behavior against a local fake provider.

Uses disposable fake auth. Never reads real user credentials or calls OpenAI.
"""
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

BIN = pathlib.Path("build/pi-bend").resolve()
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert self.headers["Authorization"] == "Bearer fixture-token"
        requests.append(body)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def event(value):
            self.wfile.write(("data: " + json.dumps(value) + "\r\n\r\n").encode())
            self.wfile.flush()

        if len(requests) == 1:
            event({"type": "response.failed", "response": {"error": {"code": "server_is_overloaded", "message": "overloaded"}}})
            return
        results = [x for x in body["input"] if x.get("type") == "function_call_output"]
        if not results:
            event({"type": "response.output_item.done", "item": {
                "type": "function_call", "id": "fc_fixture", "call_id": "call_fixture", "name": "write",
                "arguments": json.dumps({"path": "created.txt", "content": "created by native Bend 😃\n"})}})
            # Real backends can omit output here. Items must survive independently.
            event({"type": "response.completed", "response": {"output": [], "status": "completed"}})
        else:
            assert "Successfully wrote" in results[-1]["output"] or "disabled" in results[-1]["output"]
            event({"type": "response.output_text.delta", "delta": "AGENT_FIXTURE_OK"})
            event({"type": "response.output_item.done", "item": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "AGENT_FIXTURE_OK"}], "id": "msg_fixture", "status": "completed"}})
            event({"type": "response.completed", "response": {"output": [], "status": "completed"}})

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix="pi-bend-agent-") as directory:
    root = pathlib.Path(directory)
    auth = root / "auth"
    auth.mkdir()
    (auth / "auth.json").write_text(json.dumps({"openai-codex": {"type": "oauth", "access": "fixture-token", "refresh": "fixture-refresh", "expires": 9999999999999, "accountId": "fixture-account"}}))
    env = dict(os.environ, PI_CODING_AGENT_DIR=str(auth))
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env["PI_BEND_RESPONSES_URL"] = f"http://127.0.0.1:{server.server_port}/responses"
        session = root / "session.jsonl"
        result = subprocess.run([str(BIN), "--session", str(session), "-p", "create a file"], cwd=root, env=env, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        assert "AGENT_FIXTURE_OK" in result.stdout, result.stdout
        assert (root / "created.txt").read_text() == "created by native Bend 😃\n"
        assert len(requests) == 3, len(requests)
        entries = [json.loads(x) for x in session.read_text().splitlines()]
        assert entries[0]["type"] == "session" and entries[0]["version"] == 3
        assert entries[1]["parentId"] is None
        for previous, current in zip(entries[1:], entries[2:]):
            assert current["parentId"] == previous["id"]
        first_history = [e["data"] for e in entries if e.get("customType") == "pi-bend.transcript"][-1]
        assert any(x.get("type") == "function_call_output" for x in first_history)
        result = subprocess.run([str(BIN), "--session", str(session), "-p", "continue"], cwd=root, env=env, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        assert requests[-1]["input"][:-1] == first_history
        after = [json.loads(x) for x in session.read_text().splitlines()]
        assert after[len(entries)]["parentId"] == entries[-1]["id"]
        (root / "created.txt").unlink()
        result = subprocess.run([str(BIN), "--no-session", "--no-tools", "-p", "no tools"], cwd=root, env=env, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        assert not (root / "created.txt").exists()
        server.shutdown()
print("agent: tool loop, retry, item accumulation, disabled tools and session resume passed")
