#!/usr/bin/env python3
"""upstream rpc.test.ts ("RPC mode") through the native RpcClient and CLI.

Upstream runs the suite only with an Anthropic key, against Claude. Here the
CLI's openai provider is pointed (models.json, written per test by
packages/coding-agent/test/rpc.bend) at tests/parity/fake_openai.py, whose
answers are derived from each request as a model would answer it: the reply
to "What was the exact output of the echo command ..." is the echoed value
found in the request, so that test still fails if the bash output never
reached the LLM context. All 18 upstream tests run with upstream's
assertions on native one and four threads.

The same patched suite also runs under vitest with upstream's own RpcClient
and the installed pi 0.87.1 CLI against the same provider, and every test
must have the same outcome on both sides. Two upstream tests fail on
upstream itself: a one-exchange session is below keepRecentTokens, so
v0.87.1's compact() answers "Nothing to compact (session too small)"; the
port reproduces that failure rather than hiding it.

Build: sh scripts/build-cli.sh build/pi-cli, and
       sh scripts/build-pure.sh packages/coding-agent/test/rpc.bend build/rpc-test-native
"""
from upstream_pin import UPSTREAM
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/parity"))
import fake_openai  # noqa: E402

SUITE = UPSTREAM / "packages/coding-agent/test/rpc.test.ts"
CLIENT = UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-client.ts"
assert hashlib.sha256(SUITE.read_bytes()).hexdigest() == "28bb4f005cac1803df42abae071301824efe481598d25f1fabd0ce144203887f"
assert hashlib.sha256(CLIENT.read_bytes()).hexdigest() == "6d1a586cfa38fd3be62d21feacfe9e700f6e88d4fc842adcc345130acd0d57ff"
EXPECTED = {}
CLI = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
TEST = ROOT / "build/rpc-test-native"
NAMES = [
    "should get state",
    "should save messages to session file",
    "should handle manual compaction",
    "should execute bash command",
    "should add bash output to context",
    "should include bash output in LLM context",
    "should set and get thinking level",
    "should cycle thinking level",
    "should get available thinking levels",
    "should get available models",
    "should get session stats",
    "should create new session",
    "should export to HTML",
    "should get last assistant text",
    "should get session entries with since cursor",
    "should get session tree",
    "should retain pre-compaction entries in get_entries",
    "should set and get session name",
]


def last_user_text(body):
    texts = []
    for item in body.get("input", []) if isinstance(body, dict) else []:
        if item.get("role") != "user":
            continue
        content = item.get("content")
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            texts.append("".join(part.get("text", "") for part in content if isinstance(part, dict)))
    return texts[-1] if texts else ""


class Answers(fake_openai.Script):
    """Replies as a cooperative model would, from the request itself."""

    def next(self, body, path, headers):
        super().next(body, path, headers)
        text = last_user_text(body)
        if "Reply with just the word 'hello'" in text:
            return {"text": "hello"}
        if "Reply with just: test123" in text:
            return {"text": "test123"}
        if "Reply with just 'ok'" in text:
            return {"text": "ok"}
        if "What was the exact output of the echo command" in text:
            found = re.search(r"unique-\d+", json.dumps(body))
            return {"text": found.group(0) if found else "I do not know."}
        if "summar" in json.dumps(body).lower():
            return {"text": "## Goal\nGreet the assistant.\n\n## Progress\nThe assistant said hello."}
        return {"text": "Hello!"}


def serve(log):
    server = fake_openai.ThreadingHTTPServer(("127.0.0.1", 0), fake_openai.handler(Answers([], str(log) if log else None)))
    import threading
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


UPSTREAM_PI = Path("/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js")


def upstream_outcomes(url, root):
    """Upstream's own suite, client and CLI (the installed pi 0.87.1) against
    the same fake provider: {test name: None when it passes, else its error}."""
    source = SUITE.read_text()
    for old, new in [
        ('describe.skipIf(!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_OAUTH_TOKEN)("RPC mode"', 'describe("RPC mode"'),
        ('"../src/modes/rpc/rpc-client.ts"', json.dumps(str(UPSTREAM / "packages/coding-agent/src/modes/rpc/rpc-client.ts"))),
        ('cliPath: join(__dirname, "..", "dist", "cli.js")', f"cliPath: {json.dumps(str(UPSTREAM_PI))}"),
        ("env: { PI_CODING_AGENT_DIR: sessionDir },", 'env: { PI_CODING_AGENT_DIR: sessionDir, OPENAI_API_KEY: "sk-rpc-test", PI_OFFLINE: "1" },'),
        ('provider: "anthropic",', 'provider: "openai",'), ('model: "claude-sonnet-4-5",', 'model: "gpt-5-mini",'),
        ('toBe("anthropic")', 'toBe("openai")'), ('toBe("claude-sonnet-4-5")', 'toBe("gpt-5-mini")'),
        ("sessionDir = join(tmpdir(), `pi-rpc-test-${Date.now()}`);",
         "sessionDir = join(tmpdir(), `pi-rpc-test-${Date.now()}`);\n\t\tmkdirSync(sessionDir, { recursive: true });\n\t\t"
         f"writeFileSync(join(sessionDir, \"models.json\"), JSON.stringify({{ providers: {{ openai: {{ baseUrl: {json.dumps(url)} }} }} }}));"),
        ("import { existsSync, readdirSync, readFileSync, rmSync }", "import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync }"),
    ]:
        assert old in source, old
        source = source.replace(old, new)
    oracle = root / "oracle"
    (oracle / "test").mkdir(parents=True)
    (oracle / "node_modules").symlink_to(UPSTREAM / "node_modules")
    (oracle / "test/rpc.test.ts").write_text(source)
    report = oracle / "report.json"
    subprocess.run([str(UPSTREAM / "node_modules/.bin/vitest"), "run", "--root", str(oracle), "--reporter=json", f"--outputFile={report}"],
                   cwd=oracle, capture_output=True, text=True, timeout=600)
    results = json.loads(report.read_text())["testResults"][0]["assertionResults"]
    return {r["title"]: (None if r["status"] == "passed" else r["failureMessages"][0].split("\n")[0].removeprefix("Error: ")) for r in results}


def check(threads):
    with tempfile.TemporaryDirectory(prefix="pi-rpc-client-") as temporary:
        root = Path(temporary)
        server = serve(root / "requests.jsonl")
        try:
            env = dict(os.environ, BEND_THREADS=str(threads), OPENAI_API_KEY="sk-rpc-test", PI_OFFLINE="1",
                       PI_BEND_PACKAGE_DIR=str(ROOT), HOME=str(root))
            url = f"http://127.0.0.1:{server.server_address[1]}/v1"
            # The agent's cwd is a scratch directory (upstream uses its package
            # directory), so export_html's default output stays out of the tree.
            (root / "cwd").mkdir()
            result = subprocess.run([str(TEST), str(CLI), str(root / "cwd"), str(root), url],
                                    env=env, capture_output=True, text=True, timeout=600)
            expected = upstream_outcomes(url, root) if threads == 1 or not EXPECTED else EXPECTED
            EXPECTED.update(expected)
        finally:
            server.shutdown()
        outcomes = {}
        for line in result.stdout.splitlines():
            if line.startswith("PASS RPC mode > "):
                outcomes[line[len("PASS RPC mode > "):]] = None
            elif line.startswith("FAIL RPC mode > "):
                name, error = line[len("FAIL RPC mode > "):].split(": ", 1)
                outcomes[name] = error
        assert result.returncode == 0 and list(outcomes) == NAMES and sorted(expected) == sorted(NAMES), (threads, result.stdout[-2000:], result.stderr[-4000:])
        assert outcomes == expected, (threads, {n: (outcomes[n], expected[n]) for n in NAMES if outcomes[n] != expected[n]})
        stale = [n for n in NAMES if expected[n] is not None]
        print(f"native{threads}: all {len(NAMES)} upstream RPC mode tests agree with upstream's own run; {len(NAMES) - len(stale)} pass, "
              f"{len(stale)} fail on both ({'; '.join(f'{n}: {expected[n]}' for n in stale)})")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--serve"]:
        # The fake provider alone, for running upstream's client and CLI
        # against the same answers.
        import threading
        server = serve(Path(sys.argv[2]) if len(sys.argv) > 2 else None)
        print(server.server_address[1], flush=True)
        threading.Event().wait()
    for threads in (1, 4):
        if os.environ.get("PI_BEND_ONLY", f"native{threads}") == f"native{threads}":
            check(threads)
