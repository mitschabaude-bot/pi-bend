#!/usr/bin/env python3
"""--list-models applies the global proxy and preserves environment overrides.

The CLI validates proxy configuration when constructing its transport even
though listing configured credentials itself performs no OAuth refresh.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from upstream_pin import UPSTREAM  # noqa: F401

PROXY_KEYS = ("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "no_proxy", "all_proxy")
ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli-list-proxy-current")).resolve()


def case(binary, threads, global_proxy, project_proxy, explicit):
    with tempfile.TemporaryDirectory(prefix="pi-list-proxy-") as place:
        cwd = Path(place)
        agent_dir = cwd / "agent"
        agent_dir.mkdir()
        (cwd / ".pi").mkdir()
        (agent_dir / "settings.json").write_text(json.dumps({"httpProxy": global_proxy}))
        (cwd / ".pi/settings.json").write_text(json.dumps({"httpProxy": project_proxy}))
        (agent_dir / "auth.json").write_text("{}")
        env = {key: value for key, value in os.environ.items()
               if key not in PROXY_KEYS and not key.endswith("_API_KEY")}
        env.update(HOME=place, PI_CODING_AGENT_DIR=str(agent_dir), PI_SKIP_VERSION_CHECK="1",
                   BEND_THREADS=str(threads), TERM="dumb", OPENAI_API_KEY="fake-key")
        if explicit:
            env.update(HTTP_PROXY=explicit, HTTPS_PROXY=explicit)
        result = subprocess.run([str(binary), "--list-models", "gpt-5"], cwd=cwd, env=env,
                                capture_output=True, text=True, timeout=20)
        return result.returncode, result.stdout, result.stderr


def main():
    reference = shutil.which("pi")
    assert reference, "upstream pi must be installed"
    valid, invalid = "http://127.0.0.1:9", "socks5://127.0.0.1:9"
    cases = [(valid, invalid, None), (invalid, valid, None), (invalid, invalid, valid)]
    for global_proxy, project_proxy, explicit in cases:
        code, stdout, _ = case(reference, 1, global_proxy, project_proxy, explicit)
        assert code == 0, code
        # Native proxy parsing rejects an unsupported protocol at creation.
        # Undici defers this error until a request uses the proxy.
        expected = 1 if global_proxy == invalid and explicit is None else 0
        for threads in (1, 4):
            native_code, native_stdout, native_stderr = case(BINARY, threads, global_proxy, project_proxy, explicit)
            assert native_code == expected, (threads, native_code, expected, native_stderr)
            if expected == 0:
                assert native_stdout == stdout, (native_stdout, stdout)
            else:
                assert "proxy" in native_stderr.lower(), native_stderr
        print(f"native1/native4: global proxy applied; project ignored; explicit environment preserved ({expected}); valid model-list output matches pi")


if __name__ == "__main__":
    main()
