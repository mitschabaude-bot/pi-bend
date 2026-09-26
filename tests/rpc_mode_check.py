#!/usr/bin/env python3
"""upstream rpc-prompt-response-semantics.test.ts and
suite/regressions/5868-rpc-unknown-command-id.test.ts on tests/rpc-mode.bend,
plus a native supplement for extension UI requests and responses.

Build: bun build/bend-process-files/bend2/main.ts tests/rpc-mode.bend -o build/rpc-mode.js
       sh scripts/build-pure.sh tests/rpc-mode.bend build/rpc-mode-native
"""
from upstream_pin import UPSTREAM
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for source, digest in [
    ("packages/coding-agent/test/rpc-prompt-response-semantics.test.ts", "d3c38618c3e0a2541a9211cfa0a616d3fb9936142663621bd3e48d627e10912d"),
    ("packages/coding-agent/test/suite/regressions/5868-rpc-unknown-command-id.test.ts", "8d820e03ede2d75f422a26ff68c060e58c79e34d2e22a76fb6961c39448ad3c0"),
]:
    assert hashlib.sha256((UPSTREAM / source).read_bytes()).hexdigest() == digest, source

PREFLIGHT = "RPC prompt response semantics > emits one failure response when prompt preflight rejects"
NAMES = [
    PREFLIGHT,
    "RPC prompt response semantics > emits one success response when prompt preflight succeeds",
    "RPC prompt response semantics > emits one success response when prompt is queued during streaming",
    "RPC prompt response semantics > returns and clears queued steering and follow-up messages",
    "RPC unknown command responses (#5868) > preserves the request id on unknown command errors",
    # Native supplement: extension UI over the protocol (no upstream suite).
    "RPC extension UI > a select dialog is answered by its extension_ui_response",
    "RPC extension UI > stopping answers an open dialog as cancelled",
    "RPC extension UI > a command's handler can open a dialog while input is still read",
    "RPC extension UI > command-context actions go through the RPC host",
    "RPC extension UI > title, widget and editor-text requests are sent as upstream's",
    "RPC extension UI > the editor dialog answers with the client's value",
    "RPC extension UI > a dialog timeout answers as cancelled",
    "RPC extension UI > an aborted signal answers without a request",
    "RPC shutdown > ctx.shutdown() in a command ends RPC mode after its response",
    "RPC shutdown > ctx.shutdown() during a run ends RPC mode at agent_settled",
]
EXPECTED_FAILURES = set()


def check(label, command, threads=None):
    with tempfile.TemporaryDirectory(prefix="pi-rpc-mode-") as temporary:
        cwd, agent = Path(temporary, "cwd"), Path(temporary, "agent")
        cwd.mkdir()
        agent.mkdir()
        # compact must reach its session_before_compact handler.
        (agent / "settings.json").write_text('{"compaction":{"keepRecentTokens":1}}')
        env = dict(os.environ, PI_FAUX_API_KEY="faux-key")
        if threads:
            env["BEND_THREADS"] = threads
        result = subprocess.run(command + [str(cwd), str(agent)], cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
    outcomes = {line.split(" ", 1)[1]: line.startswith("PASS ") for line in result.stdout.splitlines() if line.startswith(("PASS ", "FAIL "))}
    assert result.returncode == 0 and list(outcomes) == NAMES, (label, result.stdout, result.stderr[-2000:])
    failed = {name for name, passed in outcomes.items() if not passed}
    assert failed == EXPECTED_FAILURES, (label, failed)
    print(f"{label}: {len(NAMES) - len(failed)} pass" + "".join(f"; still failing: {name}" for name in sorted(failed)))


check("Bun", ["bun", "build/rpc-mode.js"])
check("native1", ["build/rpc-mode-native"], "1")
check("native4", ["build/rpc-mode-native"], "4")
