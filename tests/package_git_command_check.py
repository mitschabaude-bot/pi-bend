"""Check package CLI Git install/update/remove with a local SSH transport."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main(binary: str) -> None:
    with tempfile.TemporaryDirectory(prefix="pi-bend-git-command-") as temp:
        root = Path(temp)
        remote = root / "remote"
        remote.mkdir()
        agent = root / "agent"
        agent.mkdir()
        project = root / "project"
        project.mkdir()
        ssh = root / "ssh"
        ssh.write_text('#!/bin/sh\nexec git-upload-pack "$PI_TEST_GIT_REMOTE"\n')
        ssh.chmod(0o755)
        env = {
            **os.environ,
            "PI_CODING_AGENT_DIR": str(agent),
            "PI_OFFLINE": "0",
            "GIT_SSH_COMMAND": str(ssh),
            "PI_TEST_GIT_REMOTE": str(remote),
        }

        def git(*args: str, cwd: Path = remote) -> str:
            return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=True).stdout.strip()

        def pi(*args: str) -> subprocess.CompletedProcess[str]:
            return subprocess.run([binary, *args], cwd=project, env=env, text=True, capture_output=True, timeout=30)

        git("init", "-b", "main")
        git("config", "user.name", "Test")
        git("config", "user.email", "test@example.org")
        (remote / "extension.txt").write_text("first\n")
        git("add", ".")
        git("commit", "-m", "first")

        source = "git:git@localhost:test/extension"
        checkout = agent / "git" / "localhost" / "test" / "extension"
        installed = pi("install", source)
        assert installed.returncode == 0 and "Installed" in installed.stdout, installed
        assert (checkout / "extension.txt").read_text() == "first\n"

        (remote / "extension.txt").write_text("second\n")
        git("add", ".")
        git("commit", "-m", "second")
        updated = pi("update", source)
        assert updated.returncode == 0 and "Updated" in updated.stdout, updated
        assert (checkout / "extension.txt").read_text() == "second\n"

        (remote / "extension.txt").write_text("third\n")
        git("add", ".")
        git("commit", "-m", "third")
        env["PI_OFFLINE"] = "1"
        skipped = pi("update", "--extensions")
        assert skipped.returncode == 0 and (checkout / "extension.txt").read_text() == "second\n", skipped
        env["PI_OFFLINE"] = "0"
        all_updated = pi("update", "--extensions")
        assert all_updated.returncode == 0 and "Updated packages" in all_updated.stdout, all_updated
        assert (checkout / "extension.txt").read_text() == "third\n"

        unmatched = pi("update", "git:git@localhost:test/other")
        assert unmatched.returncode != 0 and "No matching package" in unmatched.stderr, unmatched

        removed = pi("remove", source)
        assert removed.returncode == 0 and "Removed" in removed.stdout, removed
        assert not checkout.exists()
        print("package Git CLI: install, named/all updates, offline skip, no-match error, remove passed")


if __name__ == "__main__":
    main(sys.argv[1])
