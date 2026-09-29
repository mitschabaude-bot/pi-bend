"""Ctrl+Z stops pi's foreground job; shell fg restores the same editor."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli")).resolve()


def check(threads, project):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

    def own_terminal():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    shell = subprocess.Popen(
        ["bash", "--noprofile", "--norc", "-i"],
        cwd=project, stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=own_terminal,
        env={**os.environ, "TERM": "xterm-256color", "PS1": "SHELL_READY> ",
             "HISTFILE": "/dev/null", "PI_OFFLINE": "1", "BEND_THREADS": str(threads),
             "PI_CODING_AGENT_DIR": str(project / "agent")},
    )
    output = bytearray()

    def foreground_group():
        # The test process is outside the PTY's session, so tcgetpgrp is not
        # available here; Linux exposes the same foreground group in procfs.
        return int(Path(f"/proc/{shell.pid}/stat").read_text().rpartition(") ")[2].split()[5])

    def until(predicate, label):
        deadline = time.monotonic() + 30
        while not predicate() and time.monotonic() < deadline and shell.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
        assert predicate(), (label, shell.poll(), bytes(output[-2000:]))

    def settle():
        last_output = time.monotonic()
        deadline = last_output + 10
        while time.monotonic() - last_output < 0.7 and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                output.extend(os.read(master, 65536))
                last_output = time.monotonic()

    try:
        until(lambda: output.count(b"SHELL_READY> ") >= 1, "initial shell prompt")
        shell_settings = termios.tcgetattr(slave)
        os.write(master, f"{BINARY} --no-tools\n".encode())
        until(lambda: not termios.tcgetattr(slave)[3] & termios.ICANON and len(output) > 100, "pi raw input")
        settle()
        running_group = foreground_group()
        assert running_group != shell.pid
        os.write(master, b"\x1a")
        until(lambda: output.count(b"SHELL_READY> ") >= 2 and b"Stopped" in output, "suspended job")
        assert termios.tcgetattr(slave) == shell_settings, "shell did not regain its terminal settings"
        assert foreground_group() == shell.pid, "shell did not regain foreground"
        resume_at = len(output)
        os.write(master, b"fg\n")
        until(lambda: not termios.tcgetattr(slave)[3] & termios.ICANON and foreground_group() == running_group, "fg resumed pi")
        until(lambda: b"\x1b[?2026h" in output[resume_at:], "resumed TUI frame")
        os.write(master, b"/quit\r")
        until(lambda: output.count(b"SHELL_READY> ") >= 3, "pi exit returned to shell")
        assert termios.tcgetattr(slave) == shell_settings, "pi exit did not restore shell settings"
        os.write(master, b"exit\n")
        assert shell.wait(timeout=15) == 0, bytes(output[-2000:])
    finally:
        if shell.poll() is None:
            shell.kill()
            shell.wait()
        os.close(master)
        os.close(slave)
    print(f"native{threads}: Ctrl+Z stopped foreground pi; fg resumed its editor; exit restored shell")


with tempfile.TemporaryDirectory(prefix="pi-interactive-suspend-") as directory:
    project = Path(directory)
    for threads in (1, 4):
        check(threads, project)
