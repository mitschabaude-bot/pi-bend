"""Exercise pi's clipboard routing against real native subprocesses and OSC 52."""

import base64
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "build/clipboard-native-probe"


def run(env, *args):
    return subprocess.check_output([str(PROBE), *args], cwd=ROOT, env=env, timeout=8)


def writer(path, body):
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(0o755)


def main():
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', "sh", "scripts/build-pure.sh", "tests/clipboard-native-probe.bend", str(PROBE)], cwd=ROOT, check=True)

    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        env = os.environ.copy()
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "TERMUX_VERSION", "SSH_CONNECTION", "SSH_CLIENT", "MOSH_CONNECTION"):
            env.pop(key, None)
        env["PATH"] = f"{directory}:/usr/bin:/bin"
        env["CLIPBOARD_CAPTURE"] = str(directory / "captured")
        text = "café 日本語"
        osc = b"\x1b]52;c;" + base64.b64encode(text.encode()) + b"\x07"

        assert run(env, "copy", text) == osc + b"OK\n"
        assert run(env, "copy", "x" * 75001) == b"ERROR: Clipboard unavailable: text exceeds the OSC 52 size limit\n"

        writer(directory / "wl-copy", 'cat > "$CLIPBOARD_CAPTURE"\n')
        env["WAYLAND_DISPLAY"] = "wayland-0"
        assert run(env, "copy", text) == b"OK\n"
        assert (directory / "captured").read_text() == text

        env["SSH_CONNECTION"] = "client server"
        assert run(env, "copy", text) == osc + b"OK\n"
        env.pop("SSH_CONNECTION")

        writer(directory / "wl-paste", 'cat "$CLIPBOARD_CAPTURE"\n')
        assert run(env, "read") == b"TEXT: " + text.encode() + b"\n"

        writer(directory / "wl-paste", "exit 0\n")
        writer(directory / "xclip", "printf STALE\n")
        env["DISPLAY"] = ":99"
        assert run(env, "read") == b"EMPTY\n"  # An empty successful Wayland read must stop fallback.

        writer(directory / "wl-paste", "exit 1\n")
        assert run(env, "read") == b"TEXT: STALE\n"

        writer(directory / "wl-paste", "sleep 20\n")
        env.pop("DISPLAY")
        assert run(env, "read") == b"EMPTY\n"  # Native timeout is five seconds.

        writer(directory / "wslpath", 'printf "%s\\n" "$2"\n')
        powershell = directory / "powershell.exe"
        powershell.write_text("#!/usr/bin/python3\n" + '''import os, pathlib, re, sys
script = sys.argv[-1]
match = re.search(r"ReadAllText\\('((?:''|[^'])*)'", script)
assert match, script
path = pathlib.Path(match.group(1).replace("''", "'"))
pathlib.Path(os.environ["CLIPBOARD_CAPTURE"]).write_bytes(path.read_bytes())
pathlib.Path(os.environ["CLIPBOARD_TEMP_PATH"]).write_text(str(path))
pathlib.Path(os.environ["CLIPBOARD_TEMP_MODE"]).write_text(oct(path.stat().st_mode & 0o777))
''')
        powershell.chmod(0o755)
        env.pop("WAYLAND_DISPLAY")
        env["WSL_DISTRO_NAME"] = "Ubuntu"
        private_tmp = directory / "pi's tmp"
        private_tmp.mkdir()
        env["TMPDIR"] = str(private_tmp)
        env["CLIPBOARD_TEMP_PATH"] = str(directory / "temp-path")
        env["CLIPBOARD_TEMP_MODE"] = str(directory / "temp-mode")
        assert run(env, "copy", text) == b"OK\n"
        assert (directory / "captured").read_text() == text
        assert (directory / "temp-mode").read_text() == "0o600"
        assert not Path((directory / "temp-path").read_text()).exists()

        (directory / "captured").unlink()
        env["WT_SESSION"] = "windows-terminal"
        assert run(env, "copy", text) == osc + b"OK\n"
        assert not (directory / "captured").exists()  # PowerShell was skipped.
        assert run(env, "copy", "x" * 75001) == b"OK\n"  # Oversized OSC 52 uses interop.
        assert (directory / "captured").read_text() == "x" * 75001
        env.pop("WT_SESSION")

        env["SSH_CONNECTION"] = "client server"
        assert run(env, "copy", text) == osc + b"OK\n"
        env.pop("SSH_CONNECTION")
        writer(powershell, "exit 1\n")
        assert run(env, "copy", text) == osc + b"OK\n"  # Interop failure falls back to the terminal.

    print("native clipboard: Unicode, desktop/remote/WSL writes, OSC 52, read fallback and timeout OK")


if __name__ == "__main__":
    main()
