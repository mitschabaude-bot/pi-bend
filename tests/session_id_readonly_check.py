#!/usr/bin/env python3
"""Exact session IDs select by header, without persisting metadata-only runs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from upstream_pin import UPSTREAM  # noqa: F401


ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))


def session(path, identifier, cwd, extra=""):
    path.write_text(json.dumps({"type": "session", "version": 3, "id": identifier,
                                "timestamp": "2026-01-01T00:00:00.000Z", "cwd": str(cwd)}) + "\n" + extra)


def run(binary, threads, cwd, agent, sessions, *args):
    env = {**os.environ, "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1",
           "OPENAI_API_KEY": "fake-key", "BEND_THREADS": str(threads)}
    result = subprocess.run([str(binary), *args, "--session-dir", str(sessions)], cwd=cwd,
                            env=env, text=True, capture_output=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def cases(binary, threads):
    with tempfile.TemporaryDirectory(prefix="pi-session-id-") as place:
        root = Path(place)
        project = root / "project"
        other = root / "other"
        agent = root / "agent"
        sessions = root / "sessions"
        for directory in (project, other, agent, sessions):
            directory.mkdir()
        (agent / "auth.json").write_text("{}")

        metadata = run(binary, threads, project, agent, sessions, "--session-id", "read-only", "--help")
        assert metadata[0] == 0 and not list(sessions.iterdir()), metadata

        source = sessions / "imported-session.jsonl"
        session(source, "renamed-id", project)
        renamed = run(binary, threads, project, agent, sessions, "--session-id", "renamed-id", "--mode", "json")
        assert renamed[0] == 0 and json.loads(renamed[1].splitlines()[0])["id"] == "renamed-id", renamed
        assert [path.name for path in sessions.iterdir()] == [source.name]

        # Exact lookup still selects the right file beside a large unrelated transcript.
        large = sessions / "unrelated.jsonl"
        session(large, "unrelated-id", project, "x" * 1_000_000)
        exact = run(binary, threads, project, agent, sessions, "--session-id", "renamed-id", "--mode", "json")
        assert exact[0] == 0 and json.loads(exact[1].splitlines()[0])["id"] == "renamed-id", exact

        before_missing = set(sessions.iterdir())
        missing = run(binary, threads, project, agent, sessions, "--session-id", "fresh-id", "--mode", "json")
        assert missing[0] == 0 and "creating a new session" in missing[2], missing
        assert set(sessions.iterdir()) == before_missing

        foreign = sessions / "foreign.jsonl"
        session(foreign, "foreign-id", other)
        cross_project = run(binary, threads, project, agent, sessions, "--session-id", "foreign-id", "--mode", "json")
        assert cross_project[0] == 0 and "creating a new session" in cross_project[2], cross_project
        same_project = run(binary, threads, other, agent, sessions, "--session-id", "foreign-id", "--mode", "json")
        assert same_project[0] == 0 and same_project[2] == "", same_project

        target = sessions / "existing.jsonl"
        session(target, "existing-id", project)
        conflict = run(binary, threads, project, agent, sessions, "--fork", "renamed-id",
                       "--session-id", "existing-id", "--mode", "json")
        assert conflict[0] == 1 and conflict[1] == "" and "Session already exists with id 'existing-id'" in conflict[2], conflict
        return (metadata[0], renamed[0], exact[0], missing[2].splitlines()[0], cross_project[2].splitlines()[0],
                same_project[2], conflict[0], conflict[2].strip())


reference = shutil.which("pi")
assert reference, "upstream pi must be installed"
expected = cases(reference, 1)
for threads in (1, 4):
    actual = cases(BINARY, threads)
    assert actual == expected, (threads, expected, actual)
    print(f"native{threads}: exact IDs, renamed files, project filtering, metadata-only runs and fork conflicts match pi")
