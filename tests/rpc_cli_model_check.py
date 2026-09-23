#!/usr/bin/env python3
"""Exercise RPC model commands through the authenticated CLI runtime."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = [
    {"id": "available", "type": "get_available_models"},
    {"id": "set", "type": "set_model", "provider": "openai", "modelId": "gpt-5-mini"},
    {"id": "cycle", "type": "cycle_model"},
    {"id": "state", "type": "get_state"},
]

def check(label, executable, threads=None):
    with tempfile.TemporaryDirectory(prefix="pi-rpc-model-") as temp:
        env = {"PATH": os.environ["PATH"], "HOME": temp, "PI_CODING_AGENT_DIR": temp,
               "PI_OFFLINE": "1", "OPENAI_API_KEY": "sk-test"}
        if threads:
            env["BEND_THREADS"] = threads
        request = "".join(json.dumps(command) + "\n" for command in COMMANDS)
        output = subprocess.check_output(executable + ["--mode", "rpc", "--no-session", "--provider", "openai", "--model", "gpt-5"],
                                         input=request.encode(), cwd=temp, env=env, timeout=30)
        records = [json.loads(line) for line in output.splitlines()]
        assert [(r["id"], r["command"], r["success"]) for r in records] == [(c["id"], c["type"], True) for c in COMMANDS], (label, records)
        available = records[0]["data"]["models"]
        assert len(available) > 1 and {m["provider"] for m in available} == {"openai"}, label
        assert records[1]["data"] == next(m for m in available if m["id"] == "gpt-5-mini"), label
        cycled = records[2]["data"]
        assert cycled["model"] in available and cycled["model"]["id"] != "gpt-5-mini", label
        assert cycled["isScoped"] is False and records[3]["data"]["model"] == cycled["model"], label
        assert records[3]["data"]["thinkingLevel"] == cycled["thinkingLevel"], label
        print(f"{label}: credential-filtered catalog and CLI set/cycle state")

check("Bun", ["bun", str(ROOT / "build/pi-rpc-model.js")])
check("native1", [str(ROOT / "build/pi-rpc-model-native")], "1")
check("native4", [str(ROOT / "build/pi-rpc-model-native")], "4")
