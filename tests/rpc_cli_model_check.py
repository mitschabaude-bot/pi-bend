#!/usr/bin/env python3
"""Exercise RPC model commands through the authenticated CLI runtime."""
import json
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()).resolve()
UPSTREAM = Path(os.environ.get("PI_MONO", ROOT.parent / "pi-mono" if (ROOT.parent / "pi-mono").is_dir() else COMMON.parent.parent / "pi-mono"))
assert hashlib.sha256((UPSTREAM / "packages/coding-agent/src/core/model-resolver.ts").read_bytes()).hexdigest() == "b0119e2e18f2b480cfd714c121dda1a0b9282bc9d8caa2ead1891b34642d4ed8"
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

def scoped(label, executable, threads=None):
    with tempfile.TemporaryDirectory(prefix="pi-rpc-scope-") as temp:
        env = {"PATH": os.environ["PATH"], "HOME": temp, "PI_CODING_AGENT_DIR": temp,
               "PI_OFFLINE": "1", "OPENAI_API_KEY": "sk-test"}
        if threads:
            env["BEND_THREADS"] = threads
        request = "".join(json.dumps(command) + "\n" for command in [
            {"id": "initial", "type": "get_state"},
            {"id": "available", "type": "get_available_models"},
            {"id": "cycle", "type": "cycle_model"},
            {"id": "final", "type": "get_state"},
        ])
        args = ["--mode", "rpc", "--no-session", "--provider", "openai", "--models", "gpt-5-mini:low,gpt-5-nano:high"]
        result = subprocess.run(executable + args, input=request.encode(), cwd=temp, env=env, capture_output=True, timeout=30)
        assert result.returncode == 0, (label, result.stderr.decode())
        records = {r["id"]: r for r in map(json.loads, result.stdout.splitlines()) if r.get("type") == "response"}
        assert records["initial"]["data"]["model"]["id"] == "gpt-5-mini" and records["initial"]["data"]["thinkingLevel"] == "low", label
        assert len(records["available"]["data"]["models"]) > 2, label
        assert records["cycle"]["data"]["model"]["id"] == "gpt-5-nano", label
        assert records["cycle"]["data"]["thinkingLevel"] == "high" and records["cycle"]["data"]["isScoped"] is True, label
        assert records["final"]["data"]["model"] == records["cycle"]["data"]["model"], label
        glob = subprocess.run(executable + ["--mode", "rpc", "--no-session", "--provider", "openai", "--models", "gpt-5-n*"],
                              input=b'{"id":"cycle","type":"cycle_model"}\n', cwd=temp, env=env, capture_output=True, timeout=30)
        assert glob.returncode == 0, (label, glob.stderr.decode())
        assert next(r for r in map(json.loads, glob.stdout.splitlines()) if r.get("id") == "cycle")["data"] is None, label
        for pattern, error in [("gpt-[", "Invalid model glob pattern"), ("gpt-5-mini:bogus", "Invalid thinking level"), ("missing-model", "No models match pattern")]:
            invalid = subprocess.run(executable + ["--mode", "rpc", "--no-session", "--provider", "openai", "--models", pattern],
                                     input=b'{"id":"state","type":"get_state"}\n', cwd=temp, env=env, capture_output=True, timeout=30)
            assert invalid.returncode != 0 and error in invalid.stderr.decode() and not invalid.stdout, (label, pattern, invalid)
        (Path(temp) / "settings.json").write_text(json.dumps({"enabledModels": ["gpt-5-mini:low", "gpt-5-nano:high"]}))
        configured = subprocess.run(executable + ["--mode", "rpc", "--no-session", "--provider", "openai"],
                                    input=b'{"id":"state","type":"get_state"}\n{"id":"cycle","type":"cycle_model"}\n',
                                    cwd=temp, env=env, capture_output=True, timeout=30)
        assert configured.returncode == 0, (label, configured.stderr.decode())
        configured_responses = {r["id"]: r for r in map(json.loads, configured.stdout.splitlines()) if r.get("type") == "response"}
        assert configured_responses["state"]["data"]["model"]["id"] == "gpt-5-mini", label
        assert configured_responses["cycle"]["data"]["model"]["id"] == "gpt-5-nano" and configured_responses["cycle"]["data"]["isScoped"] is True, label
        print(f"{label}: scoped initial selection, per-model thinking, glob, and invalid-pattern rejection")

check("Bun", ["bun", str(ROOT / "build/pi-rpc-model.js")])
scoped("Bun", ["bun", str(ROOT / "build/pi-rpc-model.js")])
check("native1", [str(ROOT / "build/pi-rpc-model-native")], "1")
scoped("native1", [str(ROOT / "build/pi-rpc-model-native")], "1")
check("native4", [str(ROOT / "build/pi-rpc-model-native")], "4")
scoped("native4", [str(ROOT / "build/pi-rpc-model-native")], "4")
