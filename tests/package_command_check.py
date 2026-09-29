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

        removed = pi("remove", "./extension")
        assert removed.returncode == 0 and "Removed ./extension" in removed.stdout, removed
        assert "./extension" not in settings.read_text(), settings.read_text()
        assert "No packages installed." in pi("list").stdout

        missing = pi("install", "./missing")
        assert missing.returncode != 0 and "Path does not exist" in missing.stderr, missing
        print("package CLI: install, persist, list, trust, remove, missing path passed")


if __name__ == "__main__":
    main(sys.argv[1])
