"""Exercise the native --resume picker through a real PTY.

Run after building session-picker-driver.bend:
  python3 packages/coding-agent/test/session_picker_pty.py build/session-picker-driver
"""

import json
import os
import pty
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def session(directory: Path, cwd: Path, session_id: str, title: str | None, first: str, parent: Path | None = None) -> Path:
    path = directory / f"{session_id}.jsonl"
    header = {
        "type": "session",
        "version": 3,
        "id": session_id,
        "timestamp": "2026-09-20T00:00:00.000Z",
        "cwd": str(cwd),
    }
    if parent:
        header["parentSession"] = str(parent)
    entries = [header]
    if title:
        entries.append({"type": "session_info", "id": session_id + "-name", "parentId": None, "timestamp": "2026-09-20T00:00:00.000Z", "name": title})
    entries.append({"type": "message", "id": session_id + "-msg", "parentId": None, "timestamp": "2026-09-20T00:00:01.000Z", "message": {"role": "user", "content": first, "timestamp": 1789862401000}})
    path.write_text("".join(json.dumps(entry) + "\n" for entry in entries))
    return path


def project_directory(sessions: Path, cwd: Path) -> Path:
    directory = sessions / ("--" + str(cwd).lstrip("/").replace("/", "-") + "--")
    directory.mkdir(parents=True)
    return directory


def run(binary: Path, cwd: Path, agent: Path, sessions: Path, threads: int, keys: list[bytes]) -> str:
    master, slave = pty.openpty()
    process = subprocess.Popen(
        [str(binary), "--threads", str(threads), str(cwd), str(agent), str(sessions)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        cwd=cwd,
    )
    os.close(slave)
    chunks: list[bytes] = []

    def drain(duration: float) -> None:
        until = time.monotonic() + duration
        while time.monotonic() < until:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    chunks.append(os.read(master, 65536))
                except OSError:
                    return

    try:
        drain(0.35)
        for key in keys:
            os.write(master, key)
            drain(0.2)
        drain(0.5)
        if process.poll() is None:
            raise AssertionError("picker did not exit after selection or cancellation")
        return b"".join(chunks).decode("utf-8", "replace")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        os.close(master)


def main() -> None:
    binary = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="pi-resume-picker-") as temporary:
        root = Path(temporary)
        agent = root / "agent"
        sessions = agent / "sessions"
        local = root / "project-a"
        remote = root / "project-b"
        local.mkdir()
        remote.mkdir()
        local_dir = project_directory(sessions, local)
        remote_dir = project_directory(sessions, remote)
        parent = session(local_dir, local, "alpha", "Named alpha", "Alpha task")
        child = session(local_dir, local, "alpha-child", None, "Child branch", parent)
        other = session(remote_dir, remote, "beta", "Named beta", "Beta task")

        output = run(binary, local, agent, sessions, 1, [b"\x1b[B", b"\r"])
        assert "Child branch" in output and "PICKER SELECT " + str(child) in output, output

        output = run(binary, local, agent, sessions, 4, [b"\t", b"Beta", b"\r"])
        assert "Resume Session (All)" in output and "PICKER SELECT " + str(other) in output, output

        output = run(binary, local, agent, sessions, 1, [b"\x0e", b"\r"])
        assert "Named" in output and "PICKER SELECT " + str(parent) in output, output

        output = run(binary, local, agent, sessions, 4, [b"\x13", b"\x1b"])
        assert "Recent" in output and "PICKER CANCEL" in output, output

    print("PASS native picker PTY (threads 1 and 4)")


if __name__ == "__main__":
    main()
