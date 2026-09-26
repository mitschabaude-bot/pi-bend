"""upstream test/startup-session-name.test.ts against the native CLI.

Build first: sh scripts/build-cli.sh build/pi-cli (or set PI_BEND_CLI)."""
import datetime, json, os, pathlib, subprocess, tempfile
from upstream_pin import UPSTREAM
import hashlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = pathlib.Path(os.environ.get('PI_BEND_CLI', str(ROOT / 'build/pi-cli'))).resolve()
SOURCE = UPSTREAM / 'packages/coding-agent/test/startup-session-name.test.ts'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == '7ffdd220ed424a946c349c11910e063366e3718c247b7c1ab2cfae957f267040', SOURCE


def create_session_file(project_dir, session_file):
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
    header = {'type': 'session', 'version': 3, 'id': 'existing-session', 'timestamp': timestamp, 'cwd': str(project_dir)}
    message = {'type': 'message', 'id': 'assistant-1', 'parentId': None, 'timestamp': timestamp,
               'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'hello'}], 'provider': 'anthropic', 'model': 'claude-sonnet-4-5', 'timestamp': 0}}
    session_file.write_text(json.dumps(header) + '\n' + json.dumps(message) + '\n')


def session_info_names(session_file):
    entries = [json.loads(line) for line in session_file.read_text().strip().split('\n')]
    return [entry.get('name', '') for entry in entries if entry.get('type') == 'session_info']


# startup session name > sets --name on the selected session before runtime model validation
with tempfile.TemporaryDirectory(prefix='pi-startup-session-name-') as temporary:
    root = pathlib.Path(temporary).resolve()
    agent_dir, project_dir, session_file = root / 'agent', root / 'project', root / 'session.jsonl'
    agent_dir.mkdir()
    project_dir.mkdir()
    create_session_file(project_dir, session_file)
    env = dict(os.environ, PI_CODING_AGENT_DIR=str(agent_dir), PI_OFFLINE='1')
    result = subprocess.run([str(CLI), '--session', str(session_file), '--name', '  CLI Named Session  ', '--model', 'missing-model', '-p', 'hi'],
                            cwd=project_dir, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 1, (result.returncode, result.stderr)
    assert session_info_names(session_file) == ['CLI Named Session'], session_file.read_text()
print('startup-session-name: 1 upstream case passed')
