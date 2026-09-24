"""Model availability with stored OAuth credentials, against the installed pi 0.87.1.

upstream Models.checkProviderAuth counts a stored OAuth credential as
configured without refreshing it, so --list-models shows an expired
Anthropic OAuth provider's models and opens no connection.
"""
import json, os, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("PI_BEND_CLI", ROOT / "build/pi-cli"))
assert subprocess.run(['pi', '--version'], capture_output=True, text=True).stdout.strip() == '0.87.1'
with tempfile.TemporaryDirectory(prefix='pi-availability-') as folder:
    base = Path(folder); agent = base / 'agent'; agent.mkdir()
    (agent / 'auth.json').write_text(json.dumps({
        'anthropic': {'type': 'oauth', 'refresh': 'sk-ant-ort01-invalid', 'access': 'sk-ant-oat01-invalid', 'expires': 1000},
        'openai': {'type': 'api_key', 'key': 'sk-test-invalid'}}))
    os.chmod(agent / 'auth.json', 0o600)
    env = dict(os.environ, PI_CODING_AGENT_DIR=str(agent))
    expected = subprocess.run(['pi', '--list-models'], cwd=base, env=env, capture_output=True, text=True, timeout=120)
    for label, threads in (('native1', '1'), ('native4', '4')):
        trace = base / ('trace-' + label)
        command = ["env", f"BEND_THREADS={threads}", str(CLI), '--list-models']
        if shutil.which('strace'): command = ['strace', '-f', '-e', 'trace=connect', '-o', str(trace)] + command
        actual = subprocess.run(command, cwd=base, env=env, capture_output=True, text=True, timeout=120)
        assert actual.returncode == expected.returncode and actual.stdout == expected.stdout, (label, actual.stdout[-800:], actual.stderr[-800:])
        assert 'anthropic' in actual.stdout
        if trace.exists(): assert 'htons(443)' not in trace.read_text(), 'no OAuth refresh at startup'
        print(f'{label}: --list-models matches pi 0.87.1 with an expired OAuth credential and opens no connection')
