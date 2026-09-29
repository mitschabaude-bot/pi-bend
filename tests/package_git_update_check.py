"""Exercise managed Git package updates against a local repository."""

import subprocess
import sys
import tempfile
from pathlib import Path


def run(*args: str, cwd: Path) -> str:
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=True)
    return result.stdout.strip()


def main(binary: str) -> None:
    with tempfile.TemporaryDirectory(prefix="pi-bend-git-package-") as temp:
        root = Path(temp)
        remote = root / "remote"
        remote.mkdir()
        agent = root / "agent"
        agent.mkdir()
        checkout = agent / "git" / "github.com" / "test" / "extension"

        def git(*args: str, cwd: Path = remote) -> str:
            return run("git", *args, cwd=cwd)

        def commit(content: str) -> str:
            (remote / "extension.txt").write_text(content)
            git("add", ".")
            git("commit", "-m", content)
            return git("rev-parse", "HEAD")

        def update(ref: str = "-") -> None:
            assert run(binary, str(root), str(agent), str(remote), ref, cwd=root) == "updated"

        def assert_checkout(revision: str, content: str) -> None:
            assert git("rev-parse", "HEAD", cwd=checkout) == revision
            assert (checkout / "extension.txt").read_text() == content

        git("init", "-b", "main")
        git("config", "user.name", "Test")
        git("config", "user.email", "test@example.org")
        (remote / "package.json").write_text('{"name":"local-extension","version":"1.0.0"}\n')
        first = commit("first\n")
        git("tag", "first")
        update()
        assert_checkout(first, "first\n")
        assert (checkout / "package-lock.json").exists(), "clone should install package dependencies"

        leftover = checkout / "untracked.txt"
        leftover.write_text("keep on no-op\n")
        update()
        assert leftover.exists(), "unchanged HEAD should skip cleanup"

        marker = checkout.parent / ".extension.pi-update-incomplete"
        marker.write_text("")
        update()
        assert not leftover.exists(), "an interrupted update should finish cleanup"
        assert not marker.exists(), "completed cleanup should clear the marker"

        leftover.write_text("remove on update\n")

        second = commit("second\n")
        git("tag", "second")
        update()
        assert_checkout(second, "second\n")
        assert not leftover.exists(), "changed HEAD should clean untracked files"

        git("reset", "--hard", first)
        rewritten = commit("rewritten\n")
        update()
        assert_checkout(rewritten, "rewritten\n")

        update("first")
        assert_checkout(first, "first\n")
        update("second")
        assert_checkout(second, "second\n")
        marker.write_text("")
        update("--remove")
        assert not checkout.exists() and not marker.exists(), "removal should clear checkout and marker"
        print("managed Git lifecycle: clone, no-op, interrupted cleanup, advance, rewrite, pins, remove passed")


if __name__ == "__main__":
    main(sys.argv[1])
