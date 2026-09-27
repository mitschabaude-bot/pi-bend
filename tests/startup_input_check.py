"""Exercise real early input while managed-tool validation delays native startup."""
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


def check(binary, threads):
    with tempfile.TemporaryDirectory(prefix='pi-startup-input-') as tmp:
        root = Path(tmp)
        agent = root / '.pi/agent'
        agent.mkdir(parents=True)
        tools = root / 'tools'
        tools.mkdir()
        for name in ('fd', 'rg'):
            tool = tools / name
            tool.write_text('#!/usr/bin/python3\nimport time\ntime.sleep(2)\nprint("test tool 1.0")\n')
            tool.chmod(0o755)
        requests = root / 'requests.jsonl'
        server = fake_openai.serve([{'text': 'STARTUP-ANSWER'}], str(requests))
        (agent / 'models.json').write_text(json.dumps({'providers': {'openai': {'baseUrl': f'http://127.0.0.1:{server.server_address[1]}/v1'}}}))
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
        original = termios.tcgetattr(slave)
        env = {'HOME': tmp, 'PI_CODING_AGENT_DIR': str(agent), 'PATH': str(tools) + ':' + os.environ['PATH'], 'TERM': 'xterm-256color', 'LANG': 'C.UTF-8', 'OPENAI_API_KEY': 'sk-parity', 'PI_OFFLINE': '1', 'BEND_THREADS': str(threads), 'PI_BEND_PACKAGE_DIR': str(ROOT)}
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

        def until(predicate, description):
            deadline = time.monotonic() + 30
            while not predicate() and time.monotonic() < deadline:
                drain(.05)
            assert predicate(), (threads, description, bytes(output[-1500:]), process.poll())

        try:
            until(lambda: b'\x1b]0;' in output, 'terminal attached before managed-tool setup')
            os.write(master, b'early draft\r')
            until(lambda: b'Startup is still in progress' in output, 'startup submission feedback')
            assert not requests.exists(), 'early input started a model request'
            until(lambda: (agent / 'settings.json').exists(), 'startup version recorded')
            settings = json.loads((agent / 'settings.json').read_text())
            assert settings['lastChangelogVersion'] == '0.87.1', settings
            drain(.5)
            assert not requests.exists(), 'blocked draft was submitted automatically'
            os.write(master, b'\r')
            until(lambda: b'STARTUP-ANSWER' in output, 'preserved draft submitted after startup')
            logged = [json.loads(line) for line in requests.read_text().splitlines()]
            assert len(logged) == 1, logged
            assert 'early draft' in json.dumps(logged[0]['body']), logged
            os.write(master, b'\x03')
            drain(.2)
            os.write(master, b'\x03')
            until(lambda: process.poll() is not None, 'exit')
            assert process.returncode == 0, process.returncode
            assert termios.tcgetattr(slave) == original, 'terminal was not restored'
            print(f'native{threads}: startup feedback, retained draft, no premature request, version persistence and clean exit pass')
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
    parser.add_argument('--bend', default=str(ROOT / 'build/pi-cli-startup-input'))
    args = parser.parse_args()
    for threads in (1, 4):
        check(str(Path(args.bend).resolve()), threads)
