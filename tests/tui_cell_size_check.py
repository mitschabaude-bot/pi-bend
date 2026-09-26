"""upstream test/tui-cell-size-input.test.ts on the native TUI through a real PTY.

tests/tui-cell-size.bend focuses an input recorder; "q" stops it after
reporting the cell dimensions. Each case runs in an image-capable terminal
environment (TERM_PROGRAM=ghostty, TERM and GHOSTTY_RESOURCES_DIR unset), as
upstream's withImageTerminal. A supplementary case checks that a terminal
without image support is not queried.
"""
import errno
import fcntl
import os
import pathlib
import pty
import select
import struct
import subprocess
import sys
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ESC = b'\x1b'
QUERY = ESC + b'[16t'


def codes(data):
    return ' '.join(str(ord(c)) for c in data) + ' '


def run(command, env, script):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    process = subprocess.Popen(command, cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env)
    output = bytearray()

    def pump(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno == errno.EIO:
                        return
                    raise

    try:
        # The first frame hides the cursor; startup (and any query) precedes it.
        deadline = time.monotonic() + 8
        while ESC + b'[?25l' not in output and time.monotonic() < deadline:
            pump(0.1)
        assert ESC + b'[?25l' in output, (command, bytes(output))
        for data in script:
            os.write(master, data)
            pump(0.2)  # longer than the 50 ms escape timeout
        stderr = process.communicate(timeout=8)[1].decode(errors='replace')
        assert process.returncode == 0, (command, stderr)
        return bytes(output), stderr.splitlines()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)


def main():
    base = {k: v for k, v in os.environ.items() if k not in ('TERM', 'TERM_PROGRAM', 'GHOSTTY_RESOURCES_DIR', 'KITTY_WINDOW_ID', 'WEZTERM_PANE', 'ITERM_SESSION_ID', 'TMUX')}
    image = {**base, 'TERM_PROGRAM': 'ghostty'}
    for label, threads in (('native1', '1'), ('native4', '4')):
        command = ['build/tui-cell-size', '--threads', threads]
        output, lines = run(command, image, [ESC, b'q'])
        assert output.count(QUERY) == 1, (label, output)
        inputs = [line for line in lines if line.startswith('input:')]
        assert inputs[:-1] == ['input:' + codes('\x1b')], (label, lines)
        print(f'{label}: TUI cell size responses > forwards bare escape even when a cell size query was sent at startup')

        output, lines = run(command, image, [ESC + b'[6;20;10t', b'q'])
        assert output.count(QUERY) == 1, (label, output)
        assert [line for line in lines if line.startswith('input:')] == ['input:' + codes('q')], (label, lines)
        assert 'cells:10x20' in lines, (label, lines)
        assert lines.index('invalidated') < lines.index('input:' + codes('q')), (label, lines)
        print(f'{label}: TUI cell size responses > consumes cell size responses and still forwards later user input')

        output, lines = run(command, {**base, 'TERM': 'xterm-256color'}, [ESC + b'[6;20;10t', b'q'])
        assert QUERY not in output, (label, output)
        assert [line for line in lines if line.startswith('input:')] == ['input:' + codes('q')], (label, lines)
        print(f'{label}: supplementary: no query without image support; a reply is still consumed')


if __name__ == '__main__':
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'tests/tui-cell-size.bend', 'build/tui-cell-size'], cwd=ROOT, check=True, env={**os.environ, 'BEND_TUS': os.environ.get('BEND_TUS', '8')})
    main()
