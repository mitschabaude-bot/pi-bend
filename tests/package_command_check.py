"""Run package commands through the native CLI with isolated settings."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main(binary: str) -> None:
    with tempfile.TemporaryDirectory(prefix="pi-bend-package-cli-") as temp:
        root = Path(temp)
        agent = root / "agent"
        project = root / "project"
        extension = project / "extension"
        extension.mkdir(parents=True)
        agent.mkdir()
        env = {**os.environ, "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1"}

        def pi(*args: str) -> subprocess.CompletedProcess[str]:
            return subprocess.run([binary, *args], cwd=project, env=env, text=True, capture_output=True, timeout=30)

        first = pi("list")
        assert first.returncode == 0 and "No packages installed." in first.stdout, first

        installed = pi("install", "./extension")
        assert installed.returncode == 0 and "Installed ./extension" in installed.stdout, installed
        settings = agent / "settings.json"
        assert "../project/extension" in settings.read_text(), settings.read_text()
        listed = pi("list")
        assert listed.returncode == 0 and "User packages:" in listed.stdout and "../project/extension" in listed.stdout, listed

        (project / ".pi").mkdir()
        (project / ".pi" / "settings.json").write_text("{}\n")
        denied = pi("install", "./extension", "-l")
        assert denied.returncode != 0 and "not trusted" in denied.stderr, denied

        approved = pi("install", "--approve", "-l", "./extension")
        assert approved.returncode == 0 and "Installed ./extension" in approved.stdout, approved
        project_settings = project / ".pi" / "settings.json"
        assert "../extension" in project_settings.read_text(), project_settings.read_text()
        hidden = pi("list", "--no-approve")
        assert hidden.returncode == 0 and "Project packages:" not in hidden.stdout, hidden
        shown = pi("list", "--approve")
        assert shown.returncode == 0 and "Project packages:" in shown.stdout, shown

        updated = pi("update", "--extensions", "--approve")
        assert updated.returncode == 0 and "Updated packages" in updated.stdout, updated
        named = pi("update", "./extension", "--approve")
        assert named.returncode == 0 and "Updated ./extension" in named.stdout, named
        unmatched = pi("update", "./missing", "--approve")
        assert unmatched.returncode != 0 and "No matching package" in unmatched.stderr, unmatched

        project_removed = pi("remove", "--approve", "./extension", "-l")
        assert project_removed.returncode == 0 and "Removed ./extension" in project_removed.stdout, project_removed
        assert "../extension" not in project_settings.read_text(), project_settings.read_text()

        removed = pi("remove", "./extension")
        assert removed.returncode == 0 and "Removed ./extension" in removed.stdout, removed
        assert "./extension" not in settings.read_text(), settings.read_text()
        assert "No packages installed." in pi("list").stdout

        missing = pi("install", "./missing")
        assert missing.returncode != 0 and "Path does not exist" in missing.stderr, missing
        print("package CLI: install, persist, list, trust overrides, update matching, remove, missing path passed")


if __name__ == "__main__":
    main(sys.argv[1])
