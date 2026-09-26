"""upstream terminal-colors.test.ts "TUI.queryTerminalBackgroundColor" on the native TUI through a real PTY.

tests/tui-terminal-colors.bend reports component input, input-listener calls
and the background query result on stderr; "q" stops it. The query is
upstream's tui.queryTerminalBackgroundColor (Query.colorQuery on the running
TUI's query handle).
"""
import errno
import fcntl
import os
import pathlib
import pty
import select
import struct
import subprocess
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ESC = b'\x1b'
QUERY = ESC + b']11;?\x07'
SUITE = 'TUI.queryTerminalBackgroundColor'


class Session:
    def __init__(self, command):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        self.process = subprocess.Popen(command, cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.PIPE, env={**os.environ, 'TERM': 'xterm-256color'})
        os.close(slave)
        self.output = bytearray()
        self.errors = bytearray()

    def pump(self, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready = select.select([self.master, self.process.stderr], [], [], 0.05)[0]
            for source in ready:
                try:
                    chunk = os.read(source if source == self.master else source.fileno(), 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                (self.output if source == self.master else self.errors).extend(chunk)

    def until(self, predicate, what):
        deadline = time.monotonic() + 8
        while not predicate() and time.monotonic() < deadline:
            self.pump(0.05)
        assert predicate(), (what, bytes(self.output), bytes(self.errors))

    def lines(self):
        return self.errors.decode(errors='replace').splitlines()

    def send(self, data):
        os.write(self.master, data)
        self.pump(0.2)

    def finish(self):
        os.write(self.master, b'q')
        self.until(lambda: b'done' in self.errors or self.process.poll() is not None, 'stop')
        self.process.wait(timeout=8)
        self.pump(0.1)
        os.close(self.master)
        assert self.process.returncode == 0, self.lines()
        # Everything before the stopping "q".
        return [line for line in self.lines() if line not in ('input:113 ', 'listener:113 ', 'done')]


def run(label, command):
    s = Session(command + ['plain'])
    s.until(lambda: QUERY in s.output, 'query written')
    s.send(ESC + b']11;#ffffff\x07')
    s.until(lambda: 'background:255,255,255' in s.lines(), 'reply')
    assert s.finish() == ['background:255,255,255'], label
    print(f'{label}: {SUITE} > writes OSC 11 query and resolves with the parsed RGB reply')

    s = Session(command + ['listening'])
    s.until(lambda: QUERY in s.output, 'query written')
    s.send(ESC + b']11;#000000\x07')
    s.until(lambda: 'background:0,0,0' in s.lines(), 'reply')
    assert s.finish() == ['background:0,0,0'], label
    print(f'{label}: {SUITE} > consumes OSC 11 replies before input listeners and focused component dispatch')

    s = Session(command + ['listening'])
    s.until(lambda: QUERY in s.output, 'query written')
    s.send(ESC + b']11;not-a-color\x07')
    s.until(lambda: 'background:none' in s.lines(), 'reply')
    assert s.finish() == ['background:none'], label
    print(f'{label}: {SUITE} > consumes unparseable strict OSC 11 replies and resolves undefined')

    s = Session(command + ['listening'])
    s.until(lambda: QUERY in s.output, 'query written')
    s.send(b'x')
    s.until(lambda: 'input:120 ' in s.lines(), 'x dispatched')
    assert s.lines() == ['listener:120 ', 'input:120 '], (label, s.lines())
    s.send(ESC + b']11;#ffffff\x07')
    s.until(lambda: 'background:255,255,255' in s.lines(), 'reply')
    assert s.finish() == ['listener:120 ', 'input:120 ', 'background:255,255,255'], label
    print(f'{label}: {SUITE} > dispatches non-matching input normally while waiting for an OSC 11 reply')

    s = Session(command + ['late'])
    s.until(lambda: 'background:none' in s.lines(), 'timeout')
    s.send(ESC + b']11;#ffffff\x07')
    assert s.finish() == ['background:none'], label
    print(f'{label}: {SUITE} > keeps consuming a late OSC 11 reply after timeout')


if __name__ == '__main__':
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh', 'scripts/build-pure.sh', 'tests/tui-terminal-colors.bend', 'build/tui-terminal-colors'], cwd=ROOT, check=True, env={**os.environ, 'BEND_TUS': os.environ.get('BEND_TUS', '8')})
    for label, threads in (('native1', '1'), ('native4', '4')):
        run(label, ['build/tui-terminal-colors', '--threads', threads])
