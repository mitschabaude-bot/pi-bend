#!/usr/bin/env python3
"""Check native Anthropic PKCE URLs against the standard-library hash oracle."""

import base64
import hashlib
import os
import subprocess
import urllib.parse
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = "tests/anthropic-oauth-start.bend"
output = root / "build/anthropic-oauth-start"
subprocess.run(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", source, str(output)], cwd=root, env=dict(os.environ, PI_BEND_OPT="-O0"), check=True)

for command in ([str(output), "--threads", "1"], [str(output), "--threads", "4"]):
    seen = set()
    for _ in range(3):
        url = subprocess.check_output(command, cwd=root, text=True).strip()
        parsed = urllib.parse.urlparse(url)
        assert (parsed.scheme, parsed.netloc, parsed.path) == ("https", "claude.ai", "/oauth/authorize")
        query = urllib.parse.parse_qs(parsed.query, strict_parsing=True)
        state = query["state"][0]
        assert state not in seen and len(state) == 43
        seen.add(state)
        expected = base64.urlsafe_b64encode(hashlib.sha256(state.encode()).digest()).decode().rstrip("=")
        assert query["code_challenge"] == [expected]
        assert query["code_challenge_method"] == ["S256"]
        assert query["redirect_uri"] == ["http://localhost:53692/callback"]
        assert query["response_type"] == ["code"]
    print("Anthropic PKCE URL verified:", command)
