#!/usr/bin/env python3
"""Exercise the native Gist path without contacting GitHub."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build/session-share-gist"

with tempfile.TemporaryDirectory(prefix="pi-share-gist-") as temporary:
    directory = Path(temporary)
    html = directory / "session.html"
    html.write_text("<html>session</html>")
    fake = directory / "gh"
    fake.write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$GH_LOG"
if [ "$1" = auth ]; then
  [ "$GH_AUTH" = yes ]
elif [ "$1" = gist ]; then
  [ "$2" = create ] && [ "$3" = --public=false ] && [ "$4" = "$GH_HTML" ] || exit 4
  [ "$GH_GIST_FAIL" = yes ] && { echo 'fixture rejected' >&2; exit 5; }
  printf '%s\\n' "$GH_URL"
else
  exit 6
fi
""")
    fake.chmod(0o755)

    def run(threads, **settings):
        env = os.environ.copy()
        env.update(PATH=str(directory), GH_LOG=str(directory / "calls"), GH_HTML=str(html),
                   GH_AUTH="yes", GH_URL="https://gist.github.com/example/abc123",
                   PI_SHARE_VIEWER_URL="https://viewer.test/session/")
        env.update(settings)
        result = subprocess.run([str(BINARY), "--threads", str(threads), str(html)],
                                cwd=directory, env=env, capture_output=True, text=True, timeout=20, check=True)
        return result.stdout.strip()

    for threads in (1, 4):
        (directory / "calls").unlink(missing_ok=True)
        assert run(threads) == "SHARED https://viewer.test/session/#abc123 https://gist.github.com/example/abc123"
        assert (directory / "calls").read_text().splitlines() == ["auth status", f"gist create --public=false {html}"]
        assert run(threads, GH_AUTH="no") == "CHECK GitHub CLI is not logged in. Run 'gh auth login' first."
        assert run(threads, GH_GIST_FAIL="yes") == "FAILED Failed to create gist: fixture rejected"
        assert run(threads, GH_URL="https://gist.github.com/") == "FAILED Failed to parse gist ID from gh output"
        fake.rename(directory / "gh-disabled")
        assert run(threads) == "CHECK GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
        (directory / "gh-disabled").rename(fake)
        print(f"native{threads}: private gist, auth, command errors, malformed URL and missing gh")
