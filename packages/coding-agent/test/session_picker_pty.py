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


def run(binary: Path, cwd: Path, agent: Path, sessions: Path, threads: int, keys: list[bytes], extra_env: dict[str, str] | None = None) -> str:
    master, slave = pty.openpty()
    environment = os.environ.copy()
    environment.update(extra_env or {})
    process = subprocess.Popen(
        [str(binary), "--threads", str(threads), str(cwd), str(agent), str(sessions)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        cwd=cwd,
        env=environment,
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
            drain(0.3)
        drain(1.5)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired as error:
            raise AssertionError("picker did not exit after selection or cancellation: " + b"".join(chunks).decode("utf-8", "replace")[-2000:]) from error
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

        output = run(binary, local, agent, sessions, 1, [b"\x10", b"\x1b"])
        assert "Path on" in output and str(parent)[:30] in output, output

        output = run(binary, local, agent, sessions, 4, [b'"Named alpha"', b"\r"])
        assert "PICKER SELECT " + str(parent) in output, output

        output = run(binary, local, agent, sessions, 1, [b"\t", b"re:^beta", b"\r"])
        assert "PICKER SELECT " + str(other) in output, output

        output = run(binary, local, agent, sessions, 4, [b"re:[", b"\x1b"])
        assert "Invalid regex" in output and "PICKER CANCEL" in output, output

        output = run(binary, local, agent, sessions, 4, [b"\x04", b"\x1b", b"\r"])
        assert "Trash this session?" in output and parent.exists(), output

        fake_bin = root / "bin"
        fake_bin.mkdir()
        trash = root / "trash"
        trash.mkdir()
        gio = fake_bin / "gio"
        gio.write_text('#!/bin/sh\nprintf "%s\\n" "$1" > "$PI_TEST_TRASH_DIR/called"\nmv -- "$2" "$PI_TEST_TRASH_DIR/$(basename "$2")"\n')
        gio.chmod(0o755)
        trash_env = {"PATH": str(fake_bin) + os.pathsep + os.environ["PATH"], "PI_TEST_TRASH_DIR": str(trash)}
        output = run(binary, local, agent, sessions, 1, [b"\x04", b"\r", b"\x1b"], trash_env)
        assert "Session moved to trash" in output and "PICKER CANCEL" in output and not parent.exists(), output
        assert (trash / parent.name).exists() and (trash / "called").read_text().strip() == "trash"

        gio.write_text("#!/bin/sh\nexit 1\n")
        output = run(binary, local, agent, sessions, 4, [b"\x04", b"\r", b"\x1b"], trash_env)
        assert "Session deleted" in output and "PICKER CANCEL" in output and not child.exists(), output

        (agent / "keybindings.json").write_text('{"app.session.togglePath":"ctrl+g"}')
        output = run(binary, local, agent, sessions, 4, [b"\x07", b"\x1b"])
        assert "Path on" in output and "PICKER CANCEL" in output, output
        output = run(binary, local, agent, sessions, 1, [b"\x10", b"\x1b"])
        assert "Path on" not in output and "PICKER CANCEL" in output, output

    print("PASS native picker PTY (threads 1 and 4)")


if __name__ == "__main__":
    main()
