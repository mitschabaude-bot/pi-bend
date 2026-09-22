"""Native print-mode CLI: argument handling, help/version, exit behavior and
(optionally) live text/JSON runs against the OpenAI Responses API.

Build first: BEND_TUS=8 sh scripts/build-pure.sh packages/coding-agent/src/main.bend build/pi-cli
Live checks run when PI_BEND_LIVE=1 and OPENAI_API_KEY are set."""
import json, os, pathlib, re, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / 'pi-mono'
CLI = ROOT / 'build/pi-cli'

def source(path):
    return subprocess.check_output(['git', '-C', str(UPSTREAM), 'show', f'46c9de402:packages/coding-agent/{path}'], text=True)

def run(args, stdin=b'', env=None, timeout=120, cwd=ROOT):
    merged = dict(os.environ)
    merged.update(env or {})
    return subprocess.run([str(CLI), '--', *args], input=stdin, capture_output=True, env=merged, timeout=timeout, cwd=cwd)

def expected_help():
    text = source('src/cli/args.ts')
    start = text.index('console.log(`') + len('console.log(`')
    end = text.index('`);', start)
    body = text[start:end]
    body = re.sub(r'\$\{chalk\.bold\("([^"]*)"\)\}', r'\1', body)
    body = body.replace('${chalk.bold(APP_NAME)}', 'pi').replace('${APP_NAME}', 'pi').replace('${extensionFlagsText}', '')
    body = body.replace('${CONFIG_DIR_NAME}', '.pi')
    body = body.replace('${ENV_AGENT_DIR.padEnd(32)}', 'PI_CODING_AGENT_DIR'.ljust(32)).replace('${ENV_SESSION_DIR.padEnd(32)}', 'PI_CODING_AGENT_SESSION_DIR'.ljust(32))
    assert '${' not in body
    return body

def check(condition, name):
    if not condition:
        raise SystemExit(f'FAIL {name}')
    print(f'PASS {name}', flush=True)

version = run(['--version'])
check(version.returncode == 0 and version.stdout == (json.loads(source('package.json'))['version'] + '\n').encode() and version.stderr == b'', 'prints the version and exits 0')

help_ = run(['--help'])
check(help_.returncode == 0 and help_.stdout.decode() == expected_help() + '\n' and help_.stderr == b'', 'prints the upstream help text')

bad_mode = run(['--mode', 'bad', '-p', 'x'])
check(bad_mode.returncode == 1 and bad_mode.stdout == b'' and bad_mode.stderr.startswith(b'Error: '), 'invalid --mode reports an error and exits 1')

missing = run(['--model'])
check(missing.returncode == 1 and b'Error:' in missing.stderr, 'a flag without its value exits 1')

bad_tui = run(['--tui-mode', 'bogus', '-p', 'x'])
check(bad_tui.returncode == 1 and b'Error:' in bad_tui.stderr, 'invalid --tui-mode exits 1')

file_missing = run(['-p', '@/nonexistent/prompt.md'], stdin=b'')
check(file_missing.returncode == 1 and b'File not found' in file_missing.stderr, 'a missing @file exits 1 with a message')

unsupported = run(['--provider', 'nope', '--model', 'x', '-p', 'hi'])
check(unsupported.returncode == 1 and b'Unknown provider "nope"' in unsupported.stderr, 'an unknown provider exits 1')

# Session flags (main.ts validateForkFlags / validateSessionIdFlags, session-file-invalid.test.ts)
fork_conflict = run(['--fork', 'abc', '--session', 'def', '--continue', '-p', 'hi'])
check(fork_conflict.returncode == 1 and fork_conflict.stderr.startswith(b'Error: --fork cannot be combined with --session, --continue'), '--fork rejects --session and --continue')

id_conflict = run(['--session-id', 'abc', '--continue', '-p', 'hi'])
check(id_conflict.returncode == 1 and id_conflict.stderr.startswith(b'Error: --session-id cannot be combined with --continue'), '--session-id rejects --continue')

bad_id = run(['--session-id', 'abc-', '-p', 'hi'])
check(bad_id.returncode == 1 and bad_id.stderr.startswith(b'Error: Session id must be non-empty, contain only alphanumeric characters'), 'an invalid --session-id exits 1 with the upstream message')

with tempfile.TemporaryDirectory(prefix='pi-session-file-invalid-') as temp:
    agent_dir = pathlib.Path(temp) / 'agent'; project = pathlib.Path(temp) / 'project'
    agent_dir.mkdir(); project.mkdir()
    session_file = pathlib.Path(temp) / 'not-a-session.log'
    original = '{"type":"event","data":"not a session"}\n'
    session_file.write_text(original)
    invalid = run(['--session', str(session_file), '-p', 'hi'], env={'PI_CODING_AGENT_DIR': str(agent_dir)}, cwd=project)
    check(invalid.returncode == 1 and f'Error: Session file is not a valid pi session: {session_file}'.encode() in invalid.stderr and b'SessionManager.open' not in invalid.stderr and b'at ' not in invalid.stderr and session_file.read_text() == original, 'prints a friendly error and preserves non-session file content (session-file-invalid.test.ts)')

    missing_cwd = pathlib.Path(temp) / 'missing.jsonl'
    missing_cwd.write_text(json.dumps({'type': 'session', 'version': 3, 'id': 'session-id', 'timestamp': '2025-01-01T00:00:00.000Z', 'cwd': str(pathlib.Path(temp) / 'does-not-exist')}) + '\n')
    stale = run(['--session', str(missing_cwd), '-p', 'hi'], env={'PI_CODING_AGENT_DIR': str(agent_dir)}, cwd=project)
    check(stale.returncode == 1 and b'Stored session working directory does not exist: ' in stale.stderr and f'Session file: {missing_cwd}'.encode() in stale.stderr, 'a stored cwd that no longer exists exits 1 with the upstream message (session-cwd.ts)')

    unknown = run(['--session', 'no-such-session-id', '-p', 'hi'], env={'PI_CODING_AGENT_DIR': str(agent_dir)}, cwd=project)
    check(unknown.returncode == 1 and b"No session found matching 'no-such-session-id'" in unknown.stderr, 'an unknown --session id exits 1')

if os.environ.get('PI_BEND_LIVE') == '1' and os.environ.get('OPENAI_API_KEY'):
    text = run(['--no-tools', '--model', 'gpt-4.1-mini', '-p', 'Reply with exactly the word pong'], timeout=300)
    check(text.returncode == 0 and text.stdout.decode().strip().lower().rstrip('.') == 'pong' and text.stderr == b'', 'text mode prints the final assistant text')

    piped = run(['--no-tools', '--model', 'gpt-4.1-mini', '-p'], stdin=b'Reply with exactly the word ping\n', timeout=300)
    check(piped.returncode == 0 and piped.stdout.decode().strip().lower().rstrip('.') == 'ping', 'piped stdin becomes the prompt')

    events = run(['--no-tools', '--model', 'gpt-4.1-mini', '--mode', 'json', '-p', 'Reply with exactly the word pong'], timeout=300)
    lines = [json.loads(line) for line in events.stdout.decode().splitlines()]
    types = [event['type'] for event in lines]
    header = lines[0]
    check(events.returncode == 0 and header['type'] == 'session' and header['version'] == 3 and re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', header['id']) and header['cwd'] == str(ROOT), 'JSON mode starts with the session header')
    compact = [t for t in types if t != 'message_update']
    check(compact == ['session', 'agent_start', 'turn_start', 'message_start', 'message_end', 'message_start', 'message_end', 'turn_end', 'agent_end'], 'JSON mode emits the upstream event sequence')
    updates = [event for event in lines if event['type'] == 'message_update']
    check(updates and all('partial' not in event['assistantMessageEvent'] for event in updates) and all(set(event) == {'type', 'usage', 'assistantMessageEvent'} for event in updates), 'message_update events carry usage and snapshot-free assistant events')
    final = [event for event in lines if event['type'] == 'message_end'][-1]['message']
    check(final['role'] == 'assistant' and final['stopReason'] == 'stop' and final['content'][0]['type'] == 'text', 'the final assistant message is complete')

    with tempfile.TemporaryDirectory(prefix='pi-native-cli-tools-') as folder:
        task = run(['--tools', 'read,write', '--model', 'gpt-4.1-mini', '--mode', 'json', '-p',
                    'Use the write tool to create result.txt in the current directory with exactly the text native-cli-integration followed by a newline. Then use the read tool to verify its contents.'],
                   cwd=folder, env={'PI_CODING_AGENT_DIR': str(pathlib.Path(folder) / 'agent')}, timeout=300)
        check(task.returncode == 0 and task.stderr == b'', 'the native CLI completes a real tool task')
        check((pathlib.Path(folder) / 'result.txt').read_bytes() == b'native-cli-integration\n', 'the write tool persists the requested contents')
        task_events = [json.loads(line) for line in task.stdout.decode().splitlines()]
        completed = [event for event in task_events if event['type'] == 'tool_execution_end']
        check({'read', 'write'} <= {event['toolName'] for event in completed} and all(not event['isError'] for event in completed), 'read and write complete through the public tool registry')
        check(task_events[-1]['type'] == 'agent_end', 'the tool loop finishes with agent_end')

    wrong = run(['--no-tools', '--model', 'gpt-4.1-mini', '--api-key', 'sk-invalid', '-p', 'hi'], timeout=300)
    check(wrong.returncode == 1 and wrong.stdout == b'' and wrong.stderr.strip() != b'', 'a rejected request exits 1 with the error on stderr')

    # A stored session: its header opens the JSON stream, its context seeds the agent,
    # and the run records the thinking level; new messages are not written yet (AgentSession).
    with tempfile.TemporaryDirectory(prefix='pi-native-cli-session-') as folder:
        project = pathlib.Path(folder) / 'project'; project.mkdir()
        stored = pathlib.Path(folder) / 'stored.jsonl'
        assistant = {'role': 'assistant', 'content': [{'type': 'text', 'text': 'The secret word is marmalade.'}], 'api': 'openai-responses', 'provider': 'openai', 'model': 'gpt-4.1-mini',
                     'usage': {'input': 1, 'output': 1, 'cacheRead': 0, 'cacheWrite': 0, 'totalTokens': 2, 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0, 'total': 0}}, 'stopReason': 'stop', 'timestamp': 2}
        original = [json.dumps({'type': 'session', 'version': 3, 'id': 'stored-session', 'timestamp': '2025-01-01T00:00:00.000Z', 'cwd': str(project)}),
                    json.dumps({'type': 'message', 'id': 'aaaa0001', 'parentId': None, 'timestamp': '2025-01-01T00:00:01.000Z', 'message': {'role': 'user', 'content': 'Remember: the secret word is marmalade.', 'timestamp': 1}}),
                    json.dumps({'type': 'message', 'id': 'aaaa0002', 'parentId': 'aaaa0001', 'timestamp': '2025-01-01T00:00:02.000Z', 'message': assistant})]
        stored.write_text('\n'.join(original) + '\n')
        resumed = run(['--session', str(stored), '--no-tools', '--model', 'gpt-4.1-mini', '--mode', 'json', '-p', 'Reply with exactly the secret word from earlier in this conversation.'],
                      cwd=project, env={'PI_CODING_AGENT_DIR': str(pathlib.Path(folder) / 'agent')}, timeout=300)
        resumed_lines = [json.loads(line) for line in resumed.stdout.decode().splitlines()]
        check(resumed.returncode == 0 and resumed_lines[0] == json.loads(original[0]), 'a stored session opens the JSON stream with its own header')
        final = [event for event in resumed_lines if event['type'] == 'message_end'][-1]['message']
        check('marmalade' in final['content'][0]['text'].lower(), 'the stored context seeds the conversation')
        after = stored.read_text().splitlines()
        check(after[:3] == original and len(after) == 4 and json.loads(after[3])['type'] == 'thinking_level_change' and json.loads(after[3])['parentId'] == 'aaaa0002', 'the run records its thinking level after the stored entries and writes nothing else yet')
if os.environ.get('PI_BEND_CODEX_LIVE') == '1':
    codex = run(['--no-tools', '--provider', 'openai-codex', '--model', 'gpt-5.5', '-p', 'Reply with exactly the word pong'],
                env={'OPENAI_API_KEY': ''}, timeout=300)
    check(codex.returncode == 0 and codex.stdout.decode().strip().lower().rstrip('.') == 'pong' and codex.stderr == b'', 'Codex runs through the existing OAuth login')

if os.environ.get('PI_BEND_FIND_LIVE') == '1':
    with tempfile.TemporaryDirectory(prefix='pi-native-cli-find-') as folder:
        root = pathlib.Path(folder)
        (root / 'nested').mkdir()
        (root / 'nested' / 'needle.txt').write_text('registry integration fixture\n')
        (root / '.gitignore').write_text('hidden.txt\n')
        (root / 'hidden.txt').write_text('must be ignored\n')
        task = run(['--tools', 'find', '--provider', 'openai-codex', '--model', 'gpt-5.5', '--mode', 'json', '-p',
                    'Call the find tool exactly once with pattern **/*.txt, path ., and limit 1. Then report the path it returned.'],
                   cwd=folder, env={'OPENAI_API_KEY': ''}, timeout=300)
        check(task.returncode == 0 and task.stderr == b'', 'native CLI completes a find-only model request')
        events = [json.loads(line) for line in task.stdout.decode().splitlines()]
        completed = [event for event in events if event['type'] == 'tool_execution_end']
        check(len(completed) == 1 and completed[0]['toolName'] == 'find' and not completed[0]['isError'], 'find executes through the public registry')
        result = completed[0]['result']
        check(result['content'][0]['text'].startswith('nested/needle.txt\n\n[1 results limit reached.'), 'find preserves result content and limit notice')
        check(result['details'] == {'resultLimitReached': 1}, 'JSON events serialize typed find details')
        check(events[-1]['type'] == 'agent_end', 'find-only tool loop reaches agent_end')

print('print_cli_check: all checks passed', flush=True)
