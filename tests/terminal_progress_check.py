"""Compare interactive OSC 9;4 progress with pi using a scripted model and PTY."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/parity'))
import fake_openai

BUSY = b'\x1b]9;4;3\x07'
CLEAR = b'\x1b]9;4;0\x07'


def check(binary, threads, enabled, abort, exit_early=False):
    with tempfile.TemporaryDirectory(prefix='pi-progress-check-') as tmp:
        home = Path(tmp)
        agent = home / '.pi/agent'
        agent.mkdir(parents=True)
        server = fake_openai.serve([{'text': 'Progress response finished. ' * 8, 'chunks': 20, 'delay_ms': 100}, {'text': 'A brief session summary.', 'chunks': 5, 'delay_ms': 100}], str(home / 'requests.jsonl'))
        report_error = server.handle_error
        def report_disconnect(request, address):
            if not isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError)):
                report_error(request, address)
        server.handle_error = report_disconnect
        (agent / 'models.json').write_text(json.dumps({'providers': {'openai': {'baseUrl': f'http://127.0.0.1:{server.server_address[1]}/v1'}}}))
        (agent / 'settings.json').write_text(json.dumps({'terminal': {'showTerminalProgress': enabled}, 'compaction': {'enabled': False, 'keepRecentTokens': 32, 'reserveTokens': 1024}}))
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
        original = termios.tcgetattr(slave)
        env = {'HOME': tmp, 'PI_CODING_AGENT_DIR': str(agent), 'PATH': os.environ['PATH'], 'TERM': 'xterm-256color', 'LANG': 'C.UTF-8', 'OPENAI_API_KEY': 'sk-parity', 'PI_OFFLINE': '1', 'BEND_THREADS': str(threads), 'PI_BEND_PACKAGE_DIR': str(ROOT)}
        process = subprocess.Popen([binary, '--provider', 'openai', '--model', 'gpt-5', '--no-session'], cwd=tmp, env=env, stdin=slave, stdout=slave, stderr=slave)
        output = bytearray()

        def drain(duration):
            deadline = time.monotonic() + duration
            while time.monotonic() < deadline:
                if select.select([master], [], [], min(.1, max(0, deadline - time.monotonic())))[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break

        def until(needle, start=0):
            deadline = time.monotonic() + 30
            while needle not in output[start:] and time.monotonic() < deadline:
                drain(.1)
            assert needle in output[start:], (binary, threads, enabled, abort, needle, bytes(output[-1500:]))

        try:
            until(b'gpt-5')
            drain(.3)
            at = len(output)
            os.write(master, b'Please respond.\r')
            if enabled:
                until(BUSY, at)
            else:
                until(b'Working', at)
            if exit_early:
                drain(.3)
            elif abort:
                drain(.3)
                os.write(master, b'\x1b')
                drain(1)
            else:
                if enabled:
                    until(BUSY, output.index(BUSY, at) + len(BUSY))
                    until(CLEAR, at)
                else:
                    drain(4)
            activity = bytes(output[at:])
            if enabled:
                assert BUSY in activity, (binary, threads, activity)
                if not exit_early:
                    assert CLEAR in activity and activity.index(BUSY) < activity.index(CLEAR), (binary, threads, activity)
            else:
                assert BUSY not in activity and CLEAR not in activity, (binary, activity)
            if enabled and not abort and not exit_early:
                at = len(output)
                os.write(master, b'/compact\r')
                until(BUSY, at)
                until(CLEAR, at)
            at = len(output)
            os.write(master, b'\x03')
            drain(.2)
            os.write(master, b'\x03')
            deadline = time.monotonic() + 10
            while process.poll() is None and time.monotonic() < deadline:
                drain(.1)
            assert process.poll() == 0, (binary, process.poll(), bytes(output[-1000:]))
            drain(.1)
            assert termios.tcgetattr(slave) == original, 'raw terminal was not restored'
            assert BUSY not in output[at:], 'progress restarted after exit'
            if exit_early:
                assert CLEAR in output[at:], 'active progress was not cleared on exit'
            print(f'{Path(binary).name} threads={threads}: enabled={enabled}, abort={abort}, exit_early={exit_early}, progress and terminal restoration pass')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bend', default=str(ROOT / 'build/pi-cli-terminal-progress'))
    parser.add_argument('--reference', default='pi')
    args = parser.parse_args()
    for binary, threads in [(args.reference, 1), (args.bend, 1), (args.bend, 4)]:
        for enabled, abort, exit_early in [(True, False, False), (True, True, False), (False, False, False), (True, False, True)]:
            check(binary, threads, enabled, abort, exit_early)
